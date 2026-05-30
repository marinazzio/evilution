# frozen_string_literal: true

require "fileutils"
require "tempfile"
require "timeout"

RSpec.describe Evilution::Isolation::Fork do
  subject(:isolator) { described_class.new }

  let(:tmpfile) { Tempfile.new("fork_spec") }
  let(:original_content) { "original content" }
  let(:mutation) do
    double("Mutation", file_path: tmpfile.path, original_source: original_content)
  end

  before do
    File.write(tmpfile.path, original_content)
  end

  after do
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "returns killed when test command fails" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_killed
      expect(result.mutation).to eq(mutation)
    end

    it "returns survived when test command passes" do
      test_command = ->(_m) { { passed: true } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_survived
    end

    it "returns unresolved when test command signals unresolved" do
      test_command = ->(_m) { { passed: false, unresolved: true, error: "no spec found" } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_unresolved
      expect(result).not_to be_error
      expect(result.error_message).to eq("no spec found")
    end

    it "returns timeout when child exceeds time limit" do
      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(result).to be_timeout
    end

    # Regression for EV-86l6 / GH #662:
    # Rails wraps ActiveRecord transactions in
    # Thread.handle_interrupt(Exception => :never), which defers Timeout's
    # Thread#raise indefinitely. InProcess isolation hangs forever on such
    # mutants. Fork isolation escapes the mask via SIGKILL from the parent.
    it "kills a child stuck inside Thread.handle_interrupt(Exception => :never)" do
      test_command = lambda { |_m|
        Thread.handle_interrupt(Exception => :never) do
          loop { 1 + 1 }
        end
        { passed: true }
      }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = isolator.call(mutation:, test_command:, timeout: 0.2)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      expect(result).to be_timeout
      expect(elapsed).to be < 5 # Fork::GRACE_PERIOD (2s) + margin
    end

    it "cleans up tracked temp dirs after a timeout" do
      dir = Dir.mktmpdir("evilution")
      Evilution::TempDirTracker.register(dir)

      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(Dir.exist?(dir)).to be false
      expect(Evilution::TempDirTracker.tracked_dirs).to be_empty
    end

    it "cleans up sandbox temp directory after child timeout" do
      dirs_before = Dir.glob(File.join(Dir.tmpdir, "evilution-run*"))

      test_command = lambda { |_m|
        Dir.mktmpdir("evilution")
        sleep 10
        { passed: true }
      }

      isolator.call(mutation:, test_command:, timeout: 0.1)

      dirs_after = Dir.glob(File.join(Dir.tmpdir, "evilution-run*"))
      new_dirs = dirs_after - dirs_before
      expect(new_dirs).to be_empty
    end

    it "sends SIGTERM before SIGKILL on timeout" do
      test_command = lambda { |_m|
        Signal.trap("TERM") { exit!(42) }
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(result).to be_timeout
    end

    it "escalates to SIGKILL when child ignores SIGTERM" do
      test_command = lambda { |_m|
        Signal.trap("TERM", "IGNORE")
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(result).to be_timeout
    end

    # Kills L193 method_body_replacement (terminate_child -> `self`/`nil`):
    # if terminate_child is gutted, a timed-out child is never signalled or
    # reaped and stays alive after #call returns. The child records its own
    # pid; after the run that pid must no longer be a live process.
    it "terminates the timed-out child process so it is not left running" do
      pid_file = Tempfile.new("timed_out_child_pid")
      pid_path = pid_file.path
      pid_file.close

      test_command = lambda do |_m|
        File.write(pid_path, Process.pid.to_s)
        sleep 30
        { passed: true }
      end

      result = isolator.call(mutation:, test_command:, timeout: 0.1)
      child_pid = File.read(pid_path).strip.to_i

      expect(result).to be_timeout
      expect(child_pid).to be > 0
      expect { Process.kill(0, child_pid) }.to raise_error(Errno::ESRCH)
    ensure
      begin
        Process.kill("KILL", child_pid) if child_pid && child_pid.positive?
      rescue Errno::ESRCH
        nil
      end
      pid_file&.unlink
    end

    # Kills L194 statement_deletion / method_call_removal: the cleanup ladder
    # must send SIGTERM before escalating to SIGKILL. The child traps TERM and
    # writes a marker file before exiting; if SIGTERM is never sent the child
    # is SIGKILLed (untrappable) and the marker is never written.
    it "delivers SIGTERM to the timed-out child before escalating to SIGKILL" do
      marker_file = Tempfile.new("term_marker")
      marker_path = marker_file.path
      marker_file.close
      File.delete(marker_path)

      test_command = lambda do |_m|
        Signal.trap("TERM") do
          File.write(marker_path, "received-term")
          exit!(0)
        end
        sleep 30
        { passed: true }
      end

      result = isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(result).to be_timeout
      expect(File.exist?(marker_path)).to be true
      expect(File.read(marker_path)).to eq("received-term")
    ensure
      File.delete(marker_path) if marker_path && File.exist?(marker_path)
    end

    it "returns error when child writes empty result" do
      test_command = lambda { |_m|
        # Exit without writing a result, causing the OS to close the pipe
        exit!(0)
      }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_error
      expect(result.error_message).to eq("empty result from child")
    end

    # Regression for EV-9qh1 / GH #1176:
    # When the test command forks a grandchild process, the grandchild
    # inherits the marshal pipe's write-end via fork. If the grandchild
    # outlives the child, the pipe never EOFs and a plain `read_io.read`
    # in the parent hangs forever. The protocol must use a length-prefixed
    # payload so the parent reads exactly N bytes without depending on EOF.
    it "completes promptly when test command leaves a grandchild that keeps the pipe write-end open" do
      pid_file = Tempfile.new("grandchild_pid")
      pid_path = pid_file.path
      pid_file.close

      test_command = lambda { |_m|
        grandchild_pid = Process.fork do
          # Outlive any reasonable test bound. The grandchild inherits the
          # runtime's marshal write_io but never writes to it.
          sleep 60
        end
        File.write(pid_path, grandchild_pid.to_s)
        { passed: true }
      }

      result = nil
      Timeout.timeout(5) do
        result = isolator.call(mutation:, test_command:, timeout: 30)
      end

      expect(result).to be_survived
    ensure
      begin
        pid_str = File.read(pid_path).strip if pid_path && File.exist?(pid_path)
        Process.kill("KILL", pid_str.to_i) if pid_str && !pid_str.empty?
      rescue Errno::ESRCH, Errno::ENOENT
        nil
      end
      pid_file&.unlink
    end

    # Regression for EV-dgjv / GH #1295:
    # A grandchild that inherits write_io can write bytes that look like a
    # valid length-prefixed payload (header + body) to the parent's pipe.
    # The parent reads the payload, then reap_and_decode calls Process.wait(pid).
    # If the per-mutation child is still alive (stuck in execute_in_child waiting
    # on subject grandchildren that the mutation broke), Process.wait blocks
    # forever — the per-mutation timeout cannot fire because wait_for_result
    # already returned. The dispatcher item_timeout then kills the pool worker.
    # Fix: reap_and_decode bounds Process.wait by a deadline; if pid hasn't
    # exited, force-terminate via the same TERM/KILL ladder used on timeout.
    it "bounds reap_and_decode so a child that hasn't exited can't hang the parent" do
      pid = Process.fork { sleep 60 }
      payload = Marshal.dump(passed: true)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Timeout.timeout(8) do
        isolator.send(:reap_and_decode, pid, payload)
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be < 5
      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    ensure
      begin
        Process.kill("KILL", pid) if pid
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.waitpid(pid) if pid
      rescue Errno::ECHILD
        nil
      end
    end

    it "returns error when test command raises" do
      test_command = ->(_m) { raise "boom" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_error
      expect(result.error_message).to eq("boom")
    end

    it "returns error when test command raises SyntaxError in child" do
      test_command = ->(_m) { raise SyntaxError, "unexpected ')'" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_error
      expect(result.error_message).to include("unexpected ')'")
    end

    it "captures error_class and error_backtrace from child" do
      test_command = ->(_m) { raise ArgumentError, "bad arg" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.error_class).to eq("ArgumentError")
      expect(result.error_backtrace).to be_an(Array)
      expect(result.error_backtrace).not_to be_empty
      expect(result.error_backtrace.length).to be <= 5
    end

    it "captures error_class for SyntaxError from child" do
      test_command = ->(_m) { raise SyntaxError, "unexpected token" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.error_class).to eq("SyntaxError")
    end

    it "returns error when test command raises LoadError in child" do
      test_command = ->(_m) { raise LoadError, "cannot load such file -- foo" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_error
      expect(result.error_message).to include("cannot load such file")
    end

    it "classifies test_crashed results as killed (mutant process_abort parity)" do
      test_command = lambda do |_m|
        {
          passed: false,
          test_crashed: true,
          error: "test crashes: RuntimeError (1 crash)",
          error_class: "RuntimeError",
          error_backtrace: ["foo.rb:1"]
        }
      end

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_killed
      expect(result.error_message).to eq("test crashes: RuntimeError (1 crash)")
      expect(result.error_class).to eq("RuntimeError")
      expect(result.error_backtrace).to eq(["foo.rb:1"])
    end

    # Regression for EV-r77x / GH #788: Rails sets Encoding.default_internal to
    # UTF-8, which forces text-mode IO#write to transcode ASCII-8BIT payloads
    # (Marshal output) into UTF-8. High bytes fail. Pipes must be in binmode.
    it "round-trips binary Marshal payloads with Encoding.default_internal=UTF-8" do
      original = Encoding.default_internal
      Encoding.default_internal = Encoding::UTF_8
      test_command = lambda do |_m|
        { passed: true, blob: String.new("\xDB", encoding: Encoding::ASCII_8BIT) }
      end

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_survived
    ensure
      Encoding.default_internal = original
    end

    it "records duration" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.duration).to be > 0
    end

    # Kills L28 method_call_removal: dropping `- start_time` makes `duration`
    # an absolute CLOCK_MONOTONIC reading (process/boot uptime, easily
    # thousands of seconds) instead of the small elapsed interval.
    it "records duration as elapsed time, not an absolute clock value" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.duration).to be < 60
    end

    # Kills L50 statement_deletion / method_call_removal: the child must set
    # ENV["TMPDIR"] to the per-run sandbox directory so mutation runs cannot
    # pollute the shared system tmpdir. The child's ENV["TMPDIR"] is surfaced
    # through the result :error field (a payload key that survives decoding).
    it "sets ENV[\"TMPDIR\"] in the child to the run sandbox directory" do
      test_command = lambda do |_m|
        { passed: false, error: ENV["TMPDIR"].to_s, error_class: "TmpdirProbe" }
      end

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.error_class).to eq("TmpdirProbe")
      expect(result.error_message).to match(/evilution-run/)
    end

    # Regression for EV-wqxu / GH #1278: mutation children must Dir.chdir into
    # the sandbox so path-relativizing mutations (e.g. File.join(dir, name) ->
    # name) write into the disposable sandbox instead of the repo root.
    it "chdirs the child into the run sandbox directory" do
      test_command = lambda do |_m|
        { passed: false, error: Dir.pwd, error_class: "CwdProbe" }
      end

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.error_class).to eq("CwdProbe")
      expect(result.error_message).to match(/evilution-run/)
    end

    # Concrete leak scenario from EV-wqxu: a relative-path File.write inside
    # the mutated subject must land inside the sandbox (cleaned up on tear-down)
    # rather than the parent's CWD (typically the repo root, which would
    # accumulate litter files).
    it "does not leak files written to a relative path by the test command into the parent CWD" do
      parent_cwd = Dir.pwd
      probe_name = "evilution-cwd-leak-probe-#{Process.pid}-#{rand(1_000_000)}.tmp"

      test_command = lambda do |_m|
        File.write(probe_name, "leak")
        { passed: false }
      end

      isolator.call(mutation:, test_command:, timeout: 5)

      expect(File.exist?(File.join(parent_cwd, probe_name))).to be(false)
    ensure
      leak = File.join(parent_cwd, probe_name) if parent_cwd && probe_name
      File.delete(leak) if leak && File.exist?(leak)
    end

    # Kills L64 / L65 method_call_removal (`unless read_io.nil?` -> `unless
    # read_io`): when binary_pipe raises, read_io/write_io stay nil. The
    # original guard (`.nil?`) skips the close; the mutant guard (truthiness)
    # runs `nil.close`, raising NoMethodError that masks the original error.
    it "still surfaces the original error when cleanup runs with nil pipes" do
      allow(isolator).to receive(:binary_pipe).and_raise(RuntimeError, "pipe boom")
      test_command = ->(_m) { { passed: true } }

      expect do
        isolator.call(mutation: mutation, test_command: test_command, timeout: 5)
      end.to raise_error(RuntimeError, "pipe boom")
    end

    it "reaps the child even when wait_for_result raises (zombie-on-raise hardening)" do
      test_command = ->(_m) { { passed: true } }
      allow(isolator).to receive(:wait_for_result).and_raise(TypeError, "corrupt payload")
      allow(Process).to receive(:waitpid).and_call_original

      expect do
        isolator.call(mutation: mutation, test_command: test_command, timeout: 5)
      end.to raise_error(TypeError)

      expect(Process).to have_received(:waitpid).at_least(:once)
    end

    it "passes test_command from result to MutationResult" do
      test_command = ->(_m) { { passed: false, test_command: "rspec --format progress spec" } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.test_command).to eq("rspec --format progress spec")
    end

    it "sets test_command to nil when not in result" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.test_command).to be_nil
    end

    it "suppresses child stdout so it does not leak to parent" do
      test_command = lambda do |_m|
        $stdout.write("noisy stdout from child\n")
        { passed: false }
      end

      reader, writer = IO.pipe
      original_stdout = $stdout.dup
      $stdout.reopen(writer)

      begin
        isolator.call(mutation: mutation, test_command: test_command, timeout: 5)
        $stdout.reopen(original_stdout)
        writer.close
        captured = reader.read
      ensure
        $stdout.reopen(original_stdout)
        reader.close unless reader.closed?
        writer.close unless writer.closed?
        original_stdout.close
      end

      expect(captured).not_to include("noisy")
    end

    it "suppresses child stderr so it does not leak to parent" do
      test_command = lambda do |_m|
        $stderr.write("noisy stderr from child\n")
        { passed: false }
      end

      reader, writer = IO.pipe
      original_stderr = $stderr.dup
      $stderr.reopen(writer)

      begin
        isolator.call(mutation: mutation, test_command: test_command, timeout: 5)
        $stderr.reopen(original_stderr)
        writer.close
        captured = reader.read
      ensure
        $stderr.reopen(original_stderr)
        reader.close unless reader.closed?
        writer.close unless writer.closed?
        original_stderr.close
      end

      expect(captured).not_to include("noisy")
    end

    it "fires worker_process_start hook after fork" do
      hook_fired = false
      hooks = Evilution::Hooks::Registry.new
      hooks.register(:worker_process_start) { hook_fired = true }
      isolator = described_class.new(hooks: hooks)

      test_command = lambda do |_m|
        # hook_fired is set in the child process; verify via side effect
        { passed: hook_fired }
      end

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_survived
    end

    it "works without hooks (backwards compatible)" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_killed
    end

    it "captures parent_rss_kb before forking" do
      skip "RSS measurement unavailable" unless Evilution::Memory.rss_kb

      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.parent_rss_kb).to be_a(Integer)
      expect(result.parent_rss_kb).to be > 0
    end

    it "does not compute memory_delta_kb (cross-process comparison)" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.memory_delta_kb).to be_nil
    end

    it "isolates mutations from parent process" do
      parent_value = "original"
      test_command = lambda do |_m|
        parent_value = "mutated_in_child"
        { passed: false }
      end

      isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(parent_value).to eq("original")
    end
  end
end
