# frozen_string_literal: true

require "English"
require "fileutils"
require "tmpdir"
require_relative "../memory"
require_relative "../temp_dir_tracker"
require_relative "../child_output"
require_relative "../process_supervisor"

require_relative "../isolation"

class Evilution::Isolation::Fork
  GRACE_PERIOD = 2
  REAP_DEADLINE = 1.0
  # Bounds of one wait between liveness checks while reaping. A child that has
  # written its result exits within a millisecond or two, so the first waits
  # are short; they double towards the cap for one that takes longer.
  REAP_STEP_MIN = 0.001
  REAP_STEP_MAX = 0.05

  def initialize(hooks: nil)
    @hooks = hooks
    # EV-3aw3 / EV-5rrh step 2: the supervisor owns this path's lifecycle --
    # spawn + process-group isolation, the TERM/grace/KILL ladder, and reap +
    # sandbox removal. fork.rb keeps only the marshal-pipe read protocol.
    @supervisor = Evilution::ProcessSupervisor.new
  end

  def call(mutation:, test_command:, timeout:)
    handle = nil
    sandbox_dir = Dir.mktmpdir("evilution-run")
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    parent_rss = Evilution::Memory.rss_kb
    read_io, write_io = binary_pipe
    handle = spawn_child(read_io, write_io, sandbox_dir, mutation, test_command)
    write_io.close
    result = wait_for_result(handle, read_io, timeout)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    build_mutation_result(mutation, result, duration, parent_rss)
  ensure
    cleanup_resources(read_io, write_io, handle, sandbox_dir)
  end

  private

  # Marshal result payload is ASCII-8BIT; pipes default to text mode and may
  # transcode according to their external/internal encodings (influenced by
  # Encoding.default_external and/or Encoding.default_internal — Rails sets
  # the latter to UTF-8), failing on bytes with no mapping. Force binmode on
  # both ends.
  def binary_pipe
    read_io, write_io = IO.pipe
    read_io.binmode
    write_io.binmode
    [read_io, write_io]
  end

  # Supervisor.spawn makes the child its own process-group leader (setpgid)
  # before this block runs, so any grandchildren test_command forks inherit the
  # group and the TERM/KILL ladder sweeps the whole subtree on timeout (EV-2sh8
  # / GH #1330). The block keeps the marshal-pipe protocol: write a
  # length-prefixed payload, then exit with the pass/fail code.
  #
  # The at_exit hook covers a child that never gets that far. The normal path
  # ends in `exit!`, which skips it, so it runs only when the child is dying.
  #
  # Both reports go through method objects taken before the test command runs.
  # When the mutation under test is one of this file, the child evaluates the
  # mutated source and the methods here are replaced; a method object keeps the
  # definition the child started with, so the result is not written by the
  # mutant it describes.
  def spawn_child(read_io, write_io, sandbox_dir, mutation, test_command)
    @supervisor.spawn(sandbox_dir: sandbox_dir) do
      write = method(:write_result)
      report_death = method(:report_death)
      child_pid = Process.pid
      # A process the tests fork inherits this hook and the pipe with it; its
      # death is not the child's to report.
      at_exit { report_death.call(write_io, $ERROR_INFO, write) if Process.pid == child_pid }
      ENV["TMPDIR"] = sandbox_dir
      # Path-relativizing mutations (e.g. File.join(dir, name) -> name) would
      # otherwise write into the parent's CWD (typically the repo root) and
      # leak past the run. chdir here keeps such writes inside sandbox_dir,
      # which the supervisor removes on reap. The in_isolated_worker! flag
      # signals the rest of evilution (SpecResolver/SpecSelector/SpecAstCache/
      # MutationApplier/SourceEvaluator/Integration) to anchor project-relative
      # paths to Evilution::PROJECT_ROOT instead of the sandbox CWD.
      Dir.chdir(sandbox_dir)
      Evilution.in_isolated_worker!
      Evilution.single_mutation_process!
      read_io.close
      suppress_child_output
      @hooks.fire(:worker_process_start, mutation:) if @hooks
      result = execute_in_child(mutation, test_command)
      write.call(write_io, result)
      exit!(result[:passed] ? 0 : 1)
    end
  end

  def write_result(write_io, result)
    payload = Marshal.dump(result)
    write_io.write([payload.bytesize].pack("N"))
    write_io.write(payload)
    write_io.close
  end

  # Some exceptions reach no `rescue` in the child. `execute_in_child` leaves
  # everything that is not a ScriptError or StandardError alone, and Ruby may
  # run neither `rescue` nor `ensure` when the stack overflows through
  # `const_missing`, which a mutation of a process-wide `const_missing` does.
  # Without a result the parent sees only an exit status.
  #
  # A child that exits on purpose or on a signal keeps its status as the
  # report: the first is its own decision, the second is usually the parent's.
  def report_death(write_io, error, write)
    return if error.nil? || write_io.closed?
    return if error.is_a?(SystemExit) || error.is_a?(SignalException)

    write.call(write_io, death_result(error))
  end

  # Dying while the tests run, after the mutated source loaded, is what a test
  # that crashes does, and counts the same. Dying before that says nothing
  # about the tests.
  def death_result(error)
    testing = Evilution.died_running_tests?(error)
    phase = testing ? "while running the tests" : "before the tests ran"
    result = {
      passed: false,
      error: "child died #{phase}: #{error.class}: #{error.message}",
      error_class: error.class.name,
      error_backtrace: Array(error.backtrace).first(5)
    }
    result[:test_crashed] = true if testing
    result
  end

  # The parent owns read_io/write_io (write_io is closed right after spawn so
  # read_io can see EOF), so they are closed here rather than handed to the
  # supervisor. The supervisor reaps the child and removes the sandbox dir; on
  # the early-failure path (binary_pipe raised before spawn) handle is nil, so
  # the orphaned sandbox is removed directly.
  def cleanup_resources(read_io, write_io, handle, sandbox_dir)
    read_io.close unless read_io.nil?
    write_io.close unless write_io.nil?
    if handle
      @supervisor.terminate(handle, grace: GRACE_PERIOD)
    elsif sandbox_dir
      FileUtils.rm_rf(sandbox_dir)
    end
    restore_original_source
  end

  def restore_original_source
    Evilution::TempDirTracker.cleanup_all
  end

  def suppress_child_output
    if Evilution::ChildOutput.log_dir
      Evilution::ChildOutput.redirect!
    else
      $stdout.reopen(File::NULL, "w")
      $stderr.reopen(File::NULL, "w")
    end
  end

  def execute_in_child(mutation, test_command)
    result = test_command.call(mutation)
    { child_rss_kb: Evilution::Memory.rss_kb }.merge(result)
  rescue ScriptError, StandardError => e
    {
      passed: false,
      error: e.message,
      error_class: e.class.name,
      error_backtrace: Array(e.backtrace).first(5)
    }
  end

  # Length-prefixed read with waitpid polling. Subject specs that exercise
  # Process.fork inside test_command leave a grandchild that inherits write_io
  # via fork — if the grandchild outlives the child, a plain `read_io.read`
  # never sees EOF and hangs forever. The length prefix makes payload reads
  # bounded; the waitpid-WNOHANG check inside the poll loop lets us exit
  # promptly when the child died without writing anything.
  def wait_for_result(handle, read_io, timeout)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return timeout_result(handle) if remaining <= 0

      if read_io.wait_readable([remaining, 0.5].min)
        payload = read_payload(read_io, deadline)
        return reap_and_decode(handle, payload, read_io) if payload
      end

      next unless @supervisor.reap_nonblock(handle)

      # Child exited. Drain any final payload that arrived between
      # wait_readable timeout and the reap (race) before declaring empty.
      final = read_payload(read_io, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.1)
      return decode_payload(final, handle) if final

      return empty_result(handle)
    end
  end

  # Process.wait without a deadline can hang the parent indefinitely. The
  # per-mutation child may already have written a payload (or a grandchild may
  # have written garbage that looks like one) while the child itself is stuck
  # in execute_in_child waiting on a subject grandchild the mutation broke.
  # wait_for_result has already returned by this point, so the per-mutation
  # timeout cannot fire. Bound the wait and fall back to the TERM/KILL ladder.
  #
  # The child closes its end of the pipe right before it exits, so the wait is
  # on the pipe: it ends the moment the child lets go of it, not at the end of
  # a fixed step. A grandchild holding the pipe keeps it open past the child's
  # exit, so the waits are sliced and the child's liveness checked after each.
  def reap_and_decode(handle, payload, read_io)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + REAP_DEADLINE
    step = REAP_STEP_MIN
    pipe_open = true
    until @supervisor.reap_nonblock(handle)
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return terminate_after_reap_deadline(handle, payload) if remaining <= 0

      pipe_open = wait_for_pipe_close(read_io, [remaining, step].min, pipe_open)
      step = [step * 2, REAP_STEP_MAX].min
    end
    decode_payload(payload, handle)
  end

  def terminate_after_reap_deadline(handle, payload)
    @supervisor.terminate(handle, grace: GRACE_PERIOD)
    # The status now records OUR signal, so it cannot be reported as the
    # child's own cause of death.
    decode_payload(payload, handle, terminated: true)
  end

  # Waits up to `seconds` for every writer to close the pipe and returns
  # whether it is still open. Once it has closed it stays readable, so from
  # then on the wait is a plain pause; bytes written after the result are
  # discarded.
  def wait_for_pipe_close(read_io, seconds, pipe_open)
    unless pipe_open
      sleep(seconds)
      return false
    end
    return true unless read_io.wait_readable(seconds)

    !read_io.read_nonblock(4096, exception: false).nil?
  end

  def read_payload(read_io, deadline)
    header = read_n_bytes(read_io, 4, deadline)
    return nil unless header

    size = header.unpack1("N")
    read_n_bytes(read_io, size, deadline)
  end

  # Bounded non-blocking read. Returns `count` bytes or nil on EOF / deadline.
  # Uses `read_nonblock` so a child that wrote a partial frame (e.g. wrote the
  # header then died with a grandchild keeping write_io open) cannot extend
  # past the polling deadline.
  def read_n_bytes(read_io, count, deadline)
    return "" if count.zero?

    buf = +""
    while buf.bytesize < count
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return nil if remaining <= 0

      chunk = read_io.read_nonblock(count - buf.bytesize, exception: false)
      case chunk
      when :wait_readable
        return nil unless read_io.wait_readable([remaining, 0.5].min)
      when nil
        return nil
      else
        buf << chunk
      end
    end
    buf
  end

  # What arrives is not always what the child wrote: every process the child
  # forks inherits the write end of the pipe. A result that does not load, or
  # loads to something other than a result, costs this mutation its verdict
  # and nothing more.
  def decode_payload(data, handle = nil, terminated: false)
    return empty_result(handle, terminated: terminated) if data.nil? || data.empty?

    result = Marshal.load(data)
    return unreadable_result(handle, "expected a Hash, got #{result.class}", terminated: terminated) unless result.is_a?(Hash)

    { timeout: false }.merge(result)
  rescue TypeError, ArgumentError => e
    unreadable_result(handle, "#{e.class}: #{e.message.gsub(/\s+/, " ")}", terminated: terminated)
  end

  def empty_result(handle, terminated: false)
    { timeout: false, passed: false, error: child_death_reason(handle, terminated: terminated) }
  end

  def unreadable_result(handle, detail, terminated: false)
    ending = child_ending(handle, terminated: terminated)
    subject = ending.nil? ? "child's result" : "#{ending}; its result"
    { timeout: false, passed: false, error: "#{subject} was unreadable (#{detail})" }
  end

  # A child that wrote no payload has usually left its stdout/stderr capture
  # empty too, so its termination status is the only evidence of what happened.
  # Reporting it separates a segfault from an OOM kill from a clean early exit,
  # all of which reach this path identically.
  def child_death_reason(handle, terminated: false)
    ending = child_ending(handle, terminated: terminated)
    ending.nil? ? "empty result from child" : "#{ending} without writing a result"
  end

  def child_ending(handle, terminated: false)
    return "child was terminated after the reap deadline" if terminated

    status = handle.nil? ? nil : handle.status
    return nil unless status.is_a?(Process::Status)
    return "child exited #{status.exitstatus}" unless status.signaled?

    "child died on #{signal_name(status.termsig)}"
  end

  def signal_name(termsig)
    name = Signal.signame(termsig)
    name.nil? ? "signal #{termsig}" : "SIG#{name}"
  end

  def timeout_result(handle)
    @supervisor.terminate(handle, grace: GRACE_PERIOD)
    { timeout: true }
  end

  def classify_status(result)
    return :timeout if result[:timeout]
    return :killed if result[:test_crashed] || result[:load_crashed]
    return :unresolved if result[:unresolved]
    return :error if result[:error]
    return :survived if result[:passed]

    :killed
  end

  def build_mutation_result(mutation, result, duration, parent_rss_kb)
    status = classify_status(result)

    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: status,
      duration: duration,
      test_command: result[:test_command],
      memory: Evilution::Result::MemoryStats.from_fields(
        child_rss_kb: result[:child_rss_kb],
        parent_rss_kb: parent_rss_kb
      ),
      error: Evilution::Result::ErrorInfo.from_fields(
        message: result[:error],
        klass: result[:error_class],
        backtrace: result[:error_backtrace]
      ),
      known_failures_only: result[:known_failures_only],
      timings: mutation_timings(result, duration),
      killing_test: result[:killing_example],
      examples_run: result[:examples_run]
    )
  end

  # A timed-out run never reports its own timings. Applying a mutation takes
  # a fraction of a second, so its time is counted as the test run's.
  def mutation_timings(result, duration)
    return Evilution::Result::MutationTimings.new(test_run: duration) if result[:timeout]

    Evilution::Result::MutationTimings.from_h(result[:timings])
  end
end
