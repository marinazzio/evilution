# frozen_string_literal: true

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
  def spawn_child(read_io, write_io, sandbox_dir, mutation, test_command)
    @supervisor.spawn(sandbox_dir: sandbox_dir) do
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
      read_io.close
      suppress_child_output
      @hooks.fire(:worker_process_start, mutation:) if @hooks
      result = execute_in_child(mutation, test_command)
      payload = Marshal.dump(result)
      write_io.write([payload.bytesize].pack("N"))
      write_io.write(payload)
      write_io.close
      exit!(result[:passed] ? 0 : 1)
    end
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
        return reap_and_decode(handle, payload) if payload
      end

      next unless @supervisor.reap_nonblock(handle)

      # Child exited. Drain any final payload that arrived between
      # wait_readable timeout and the reap (race) before declaring empty.
      final = read_payload(read_io, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.1)
      return decode_payload(final) if final

      return empty_result
    end
  end

  # Process.wait without a deadline can hang the parent indefinitely. The
  # per-mutation child may already have written a payload (or a grandchild may
  # have written garbage that looks like one) while the child itself is stuck
  # in execute_in_child waiting on a subject grandchild the mutation broke.
  # wait_for_result has already returned by this point, so the per-mutation
  # timeout cannot fire. Bound the wait and fall back to the TERM/KILL ladder.
  def reap_and_decode(handle, payload)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + REAP_DEADLINE
    loop do
      break if @supervisor.reap_nonblock(handle)

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        @supervisor.terminate(handle, grace: GRACE_PERIOD)
        break
      end
      sleep 0.05
    end
    decode_payload(payload)
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

  def decode_payload(data)
    return empty_result if data.nil? || data.empty?

    { timeout: false }.merge(Marshal.load(data))
  end

  def empty_result
    { timeout: false, passed: false, error: "empty result from child" }
  end

  def timeout_result(handle)
    @supervisor.terminate(handle, grace: GRACE_PERIOD)
    { timeout: true }
  end

  def classify_status(result)
    return :timeout if result[:timeout]
    return :killed if result[:test_crashed]
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
      )
    )
  end
end
