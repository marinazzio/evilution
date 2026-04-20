# frozen_string_literal: true

require "tempfile"

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

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_killed
      expect(result.mutation).to eq(mutation)
    end

    it "returns survived when test command passes" do
      test_command = ->(_m) { { passed: true } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_survived
    end

    it "returns unresolved when test command signals unresolved" do
      test_command = ->(_m) { { passed: false, unresolved: true, error: "no spec found" } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_unresolved
      expect(result).not_to be_error
      expect(result.error_message).to eq("no spec found")
    end

    it "returns timeout when child exceeds time limit" do
      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

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
      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 0.2)
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

      isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

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

      isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

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

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

      expect(result).to be_timeout
    end

    it "escalates to SIGKILL when child ignores SIGTERM" do
      test_command = lambda { |_m|
        Signal.trap("TERM", "IGNORE")
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 0.1)

      expect(result).to be_timeout
    end

    it "returns error when child writes empty result" do
      test_command = lambda { |_m|
        # Exit without writing a result, causing the OS to close the pipe
        exit!(0)
      }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_error
      expect(result.error_message).to eq("empty result from child")
    end

    it "returns error when test command raises" do
      test_command = ->(_m) { raise "boom" }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_error
      expect(result.error_message).to eq("boom")
    end

    it "returns error when test command raises SyntaxError in child" do
      test_command = ->(_m) { raise SyntaxError, "unexpected ')'" }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_error
      expect(result.error_message).to include("unexpected ')'")
    end

    it "captures error_class and error_backtrace from child" do
      test_command = ->(_m) { raise ArgumentError, "bad arg" }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.error_class).to eq("ArgumentError")
      expect(result.error_backtrace).to be_an(Array)
      expect(result.error_backtrace).not_to be_empty
      expect(result.error_backtrace.length).to be <= 5
    end

    it "captures error_class for SyntaxError from child" do
      test_command = ->(_m) { raise SyntaxError, "unexpected token" }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.error_class).to eq("SyntaxError")
    end

    it "returns error when test command raises LoadError in child" do
      test_command = ->(_m) { raise LoadError, "cannot load such file -- foo" }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

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

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result).to be_killed
      expect(result.error_message).to eq("test crashes: RuntimeError (1 crash)")
      expect(result.error_class).to eq("RuntimeError")
      expect(result.error_backtrace).to eq(["foo.rb:1"])
    end

    it "records duration" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation: mutation, test_command: test_command, timeout: 5)

      expect(result.duration).to be > 0
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
