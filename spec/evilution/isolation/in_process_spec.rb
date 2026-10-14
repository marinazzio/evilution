# frozen_string_literal: true

require "fileutils"
require "stringio"
require "tempfile"
require "evilution/isolation/in_process"

RSpec.describe Evilution::Isolation::InProcess do
  subject(:isolator) { described_class.new }

  let(:mutation) { double("Mutation", file_path: "lib/example.rb", original_source: "original") }

  describe "#call" do
    it "returns killed when test command fails" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_killed
      expect(result.mutation).to eq(mutation)
    end

    it "carries the known-failures flag of a failed run" do
      test_command = ->(_m) { { passed: false, known_failures_only: true } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_killed
      expect(result.known_failures_only?).to be(true)
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

    it "returns timeout when execution exceeds time limit" do
      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(result).to be_timeout
    end

    # A test framework rescues what a test raises and moves on to the next
    # one, which may reach the same endless loop.
    it "returns timeout when the run rescues the error and carries on" do
      test_command = lambda { |_m|
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        begin
          sleep 10
        rescue NoMemoryError, SignalException, SystemExit
          raise
        rescue Exception # rubocop:disable Lint/RescueException
          nil
        end
        sleep 0.01 while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        { passed: true }
      }

      result = isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(result).to be_timeout
    end

    it "stops the run with an exception test frameworks let through" do
      expect(described_class::Expired.ancestors).to include(SignalException)
    end

    # Some test tooling takes an Interrupt for the user's Ctrl-C: it rescues it
    # and skips every test from then on, in that run and in the ones after it.
    it "returns timeout when the run rescues Interrupt and carries on" do
      test_command = lambda { |_m|
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        begin
          sleep 10
        rescue Interrupt
          nil
        end
        sleep 0.01 while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        { passed: true }
      }

      result = isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(result).to be_timeout
    end

    it "returns error, not timeout, when the code under test raises Timeout::Error itself" do
      test_command = ->(_m) { raise Timeout::Error, "upstream took too long" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_error
      expect(result).not_to be_timeout
      expect(result.error_message).to eq("upstream took too long")
    end

    # Fork isolation reports a child that died on such an exception; here the
    # exception would otherwise leave the isolator and end the whole run.
    describe "an exception outside StandardError" do
      it "is killed when it left the test run" do
        test_command = lambda do |_m|
          Evilution.while_running_tests { raise SystemStackError, "stack level too deep" }
        end

        result = isolator.call(mutation:, test_command:, timeout: 5)

        expect(result).to be_killed
        expect(result.error_class).to eq("SystemStackError")
        expect(result.error_message).to eq("test run ended by SystemStackError: stack level too deep")
      end

      it "is an error when it was raised before the tests ran" do
        test_command = ->(_m) { raise SystemStackError, "stack level too deep" }

        result = isolator.call(mutation:, test_command:, timeout: 5)

        expect(result).to be_error
        expect(result.error_class).to eq("SystemStackError")
        expect(result.error_message).to eq("SystemStackError: stack level too deep")
      end

      it "captures the backtrace" do
        test_command = ->(_m) { raise Exception, "bare" } # rubocop:disable Lint/RaiseException

        result = isolator.call(mutation:, test_command:, timeout: 5)

        expect(result.error_class).to eq("Exception")
        expect(result.error_backtrace.length).to be_between(1, 5)
      end

      it "lets a request to exit through" do
        test_command = ->(_m) { exit(3) }

        expect { isolator.call(mutation:, test_command:, timeout: 5) }.to raise_error(SystemExit)
      end

      it "lets a signal through" do
        test_command = ->(_m) { raise Interrupt }

        expect { isolator.call(mutation:, test_command:, timeout: 5) }.to raise_error(Interrupt)
      end
    end

    it "returns error when test command raises" do
      test_command = ->(_m) { raise "boom" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_error
      expect(result.error_message).to eq("boom")
    end

    it "captures error_class and error_backtrace when test command raises" do
      test_command = ->(_m) { raise ArgumentError, "bad arg" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.error_class).to eq("ArgumentError")
      expect(result.error_backtrace).to be_an(Array)
      expect(result.error_backtrace).not_to be_empty
      expect(result.error_backtrace.length).to be <= 5
    end

    it "captures error_class for SyntaxError" do
      test_command = ->(_m) { raise SyntaxError, "unexpected token" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.error_class).to eq("SyntaxError")
    end

    it "returns error when test command raises SyntaxError" do
      test_command = ->(_m) { raise SyntaxError, "unexpected ')'" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_error
      expect(result.error_message).to include("unexpected ')'")
    end

    it "returns error when test command raises LoadError" do
      test_command = ->(_m) { raise LoadError, "cannot load such file -- foo" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_error
      expect(result.error_message).to include("cannot load such file")
    end

    it "classifies a mutant that crashed the load of its file as killed" do
      test_command = lambda do |_m|
        {
          passed: false,
          load_crashed: true,
          error: "load failed: NoMethodError: undefined method 'map' for nil",
          error_class: "NoMethodError",
          error_backtrace: ["foo.rb:1"]
        }
      end

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_killed
      expect(result.error_message).to eq("load failed: NoMethodError: undefined method 'map' for nil")
      expect(result.error_class).to eq("NoMethodError")
      expect(result.error_backtrace).to eq(["foo.rb:1"])
    end

    it "classifies a load failure that was not traced to the mutant as an error" do
      test_command = ->(_m) { { passed: false, error: "NoMethodError: nope", error_class: "NoMethodError" } }

      expect(isolator.call(mutation:, test_command:, timeout: 5)).to be_error
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

    it "records duration" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.duration).to be > 0
    end

    it "records duration as elapsed seconds, not the absolute monotonic clock" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.duration).to be < 60
    end

    it "merges timeout: false into a passing result so it is not classified as timeout" do
      test_command = ->(_m) { { passed: true } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_survived
      expect(result).not_to be_timeout
    end

    it "passes test_command from result to MutationResult" do
      test_command = ->(_m) { { passed: false, test_command: "rspec spec/foo_spec.rb" } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.test_command).to eq("rspec spec/foo_spec.rb")
    end

    it "sets test_command to nil when not in result" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.test_command).to be_nil
    end

    it "suppresses stdout during execution" do
      test_command = lambda { |_m|
        $stdout.write("noisy stdout\n")
        { passed: false }
      }

      output = StringIO.new
      original = $stdout
      $stdout = output
      begin
        isolator.call(mutation:, test_command:, timeout: 5)
      ensure
        $stdout = original
      end

      expect(output.string).not_to include("noisy")
    end

    it "suppresses stderr during execution" do
      test_command = lambda { |_m|
        $stderr.write("noisy stderr\n")
        { passed: false }
      }

      output = StringIO.new
      original = $stderr
      $stderr = output
      begin
        isolator.call(mutation:, test_command:, timeout: 5)
      ensure
        $stderr = original
      end

      expect(output.string).not_to include("noisy")
    end

    it "restores $stdout to its original object after a normal run" do
      original_stdout = $stdout

      test_command = ->(_m) { { passed: false } }
      isolator.call(mutation:, test_command:, timeout: 5)

      expect($stdout).to equal(original_stdout)
    end

    it "restores $stderr to its original object after a normal run" do
      original_stderr = $stderr

      test_command = ->(_m) { { passed: false } }
      isolator.call(mutation:, test_command:, timeout: 5)

      expect($stderr).to equal(original_stderr)
    end

    it "restores $stdout and $stderr after timeout" do
      original_stdout = $stdout
      original_stderr = $stderr

      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      isolator.call(mutation:, test_command:, timeout: 0.1)

      expect($stdout).to eq(original_stdout)
      expect($stderr).to eq(original_stderr)
    end

    it "does not buffer output in memory during execution" do
      test_command = lambda { |_m|
        $stdout.write("x" * 10_000)
        $stderr.write("y" * 10_000)
        expect($stdout).not_to be_a(StringIO)
        expect($stderr).not_to be_a(StringIO)
        { passed: false }
      }

      isolator.call(mutation:, test_command:, timeout: 5)
    end

    it "captures parent_rss_kb (RSS before execution)" do
      skip "RSS measurement unavailable" unless Evilution::Memory.rss_kb

      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.parent_rss_kb).to be_a(Integer)
      expect(result.parent_rss_kb).to be > 0
    end

    it "does not close /dev/null handles between calls (formatter reuse safe)" do
      stdout_ref = nil
      test_command = lambda { |_m|
        stdout_ref = $stdout
        { passed: false }
      }

      isolator.call(mutation:, test_command:, timeout: 5)
      captured_first = stdout_ref

      isolator.call(mutation:, test_command:, timeout: 5)

      expect(captured_first).not_to be_closed
    end

    it "does not interfere with $LOADED_FEATURES" do
      features_before = $LOADED_FEATURES.dup

      test_command = ->(_m) { { passed: false } }
      isolator.call(mutation:, test_command:, timeout: 5)

      expect($LOADED_FEATURES).to eq(features_before)
    end

    it "reports the rss delta (after minus before) for a normal run" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(1000, 1500)
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.memory_delta_kb).to eq(500)
    end

    it "reports the rss before the run as the parent's and the rss after as the child's" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(1000, 1500)
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect([result.parent_rss_kb, result.child_rss_kb]).to eq([1000, 1500])
    end

    it "reports a negative rss delta when memory shrinks during a run" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(2000, 1200)
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.memory_delta_kb).to eq(-800)
    end

    it "leaves memory delta nil for a timed-out run instead of computing rss math" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(1000, 1500)
      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(result).to be_timeout
      expect(result.memory_delta_kb).to be_nil
    end

    it "computes a non-nil memory delta for a non-timeout run" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(1000, 1500)
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).not_to be_timeout
      expect(result.memory_delta_kb).not_to be_nil
    end

    it "leaves memory delta nil when rss is unavailable" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(nil)
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.memory_delta_kb).to be_nil
    end

    # Regression for EV-wqxu / GH #1278: the in-process isolator must sandbox
    # the working directory around the test command so path-relativizing
    # mutations cannot pollute the repo. The chdir must restore the parent
    # CWD even when the test command times out or raises.
    it "runs the test command in a per-run sandbox CWD and restores the parent CWD" do
      original_cwd = Dir.pwd
      observed_cwd = nil
      test_command = lambda do |_m|
        observed_cwd = Dir.pwd
        { passed: false }
      end

      isolator.call(mutation:, test_command:, timeout: 5)

      expect(observed_cwd).not_to eq(original_cwd)
      expect(observed_cwd).to match(/evilution-run/)
      expect(Dir.pwd).to eq(original_cwd)
    end

    it "cleans up the sandbox CWD after the call so per-call dirs do not accumulate" do
      observed_cwd = nil
      test_command = lambda do |_m|
        observed_cwd = Dir.pwd
        File.write("leak-probe.tmp", "x")
        { passed: false }
      end

      isolator.call(mutation:, test_command:, timeout: 5)

      expect(observed_cwd).not_to be_nil
      expect(Dir.exist?(observed_cwd)).to be(false)
    end

    it "restores the parent CWD after a timeout" do
      original_cwd = Dir.pwd
      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(Dir.pwd).to eq(original_cwd)
    end

    it "restores the parent CWD after the test command raises" do
      original_cwd = Dir.pwd
      test_command = ->(_m) { raise "boom" }

      isolator.call(mutation:, test_command:, timeout: 5)

      expect(Dir.pwd).to eq(original_cwd)
    end

    it "does not leak files written to a relative path by the test command into the parent CWD" do
      parent_cwd = Dir.pwd
      probe_name = "evilution-in-process-leak-probe-#{Process.pid}-#{rand(1_000_000)}.tmp"
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
  end

  # A mutation can take the Ruby process down in a way no `rescue` sees. The
  # run is lost then, and the last thing it can do is say which mutation it was
  # and that fork isolation would have contained it.
  describe ".report_death" do
    let(:stream) { StringIO.new }
    let(:named_mutation) { double("Mutation", to_s: "constant_namespace_strip: lib/example.rb:202") }
    let(:error) { SystemStackError.new("stack level too deep") }

    after { described_class.unwatch }

    it "names the mutation the process was testing" do
      described_class.watch(named_mutation)

      described_class.report_death(error, stream:)

      expect(stream.string).to eq(
        "[evilution] the run died while testing a mutation under in-process isolation: " \
        "constant_namespace_strip: lib/example.rb:202 (SystemStackError: stack level too deep). " \
        "In-process isolation cannot contain a mutation that takes the Ruby process down; " \
        "re-run with --isolation fork.\n"
      )
    end

    it "writes to the error stream as it was before the mutation was tested" do
      saved = $stderr
      $stderr = stream
      described_class.watch(named_mutation)
      $stderr = described_class.null_err

      described_class.report_death(error)

      expect(stream.string).to include("constant_namespace_strip: lib/example.rb:202")
    ensure
      $stderr = saved
    end

    # The process is then ended without the flush a normal exit does, and the
    # stream may be one that buffers: `$stderr` reassigned to a file.
    it "pushes the notice out of a stream that buffers" do
      Tempfile.create("stderr") do |file|
        file.sync = false
        described_class.watch(named_mutation)

        described_class.report_death(error, stream: file)

        expect(File.read(file.path)).to include("constant_namespace_strip: lib/example.rb:202")
      end
    end

    it "says nothing when no mutation was being tested" do
      described_class.report_death(error, stream:)

      expect(stream.string).to eq("")
    end

    it "says nothing once the mutation is done" do
      described_class.watch(named_mutation)
      described_class.unwatch

      described_class.report_death(error, stream:)

      expect(stream.string).to eq("")
    end

    it "says nothing when the process is not dying on an exception" do
      described_class.watch(named_mutation)

      described_class.report_death(nil, stream:)

      expect(stream.string).to eq("")
    end

    it "says nothing when the process was asked to exit" do
      described_class.watch(named_mutation)

      described_class.report_death(SystemExit.new(1), stream:)

      expect(stream.string).to eq("")
    end

    it "says nothing in a process forked while the mutation was tested" do
      described_class.watch(named_mutation)
      read_io, write_io = IO.pipe

      pid = fork do
        read_io.close
        described_class.report_death(error, stream: write_io)
        write_io.close
        exit!(0)
      end
      write_io.close
      Process.wait(pid)

      expect(read_io.read).to eq("")
    end
  end

  # A run that died measured nothing, and the process has to end with the
  # status of a tool error rather than Ruby's own for an uncaught exception.
  # The death is on record for whoever decides that status.
  describe ".died?" do
    let(:stream) { StringIO.new }
    let(:named_mutation) { double("Mutation", to_s: "constant_namespace_strip: lib/example.rb:202") }
    let(:error) { SystemStackError.new("stack level too deep") }

    after { described_class.unwatch }

    it "is false while nothing has died" do
      described_class.watch(named_mutation)

      expect(described_class.died?).to be(false)
    end

    it "is true once the death of a mutation under test was reported" do
      described_class.watch(named_mutation)

      described_class.report_death(error, stream:)

      expect(described_class.died?).to be(true)
    end

    it "is false when no mutation was being tested" do
      described_class.report_death(error, stream:)

      expect(described_class.died?).to be(false)
    end

    it "is false when the process is not dying on an exception" do
      described_class.watch(named_mutation)

      described_class.report_death(nil, stream:)

      expect(described_class.died?).to be(false)
    end

    it "is false when the process was asked to exit" do
      described_class.watch(named_mutation)

      described_class.report_death(SystemExit.new(1), stream:)

      expect(described_class.died?).to be(false)
    end

    # A Ctrl-C keeps the status Ruby gives it.
    it "is false when the process was interrupted" do
      described_class.watch(named_mutation)

      described_class.report_death(Interrupt.new, stream:)

      expect(described_class.died?).to be(false)
    end

    it "is forgotten with the mutation" do
      described_class.watch(named_mutation)
      described_class.report_death(error, stream:)

      described_class.unwatch

      expect(described_class.died?).to be(false)
    end
  end

  describe "watching the mutation under test" do
    after { described_class.unwatch }

    it "watches the mutation while the test command runs" do
      seen = nil
      test_command = lambda do |_m|
        seen = described_class.watched
        { passed: true }
      end

      isolator.call(mutation:, test_command:, timeout: 5)

      expect(seen).to eq(mutation)
    end

    it "stops watching when the test command returns" do
      isolator.call(mutation:, test_command: ->(_m) { { passed: true } }, timeout: 5)

      expect(described_class.watched).to be_nil
    end

    it "stops watching when the test command raises" do
      isolator.call(mutation:, test_command: ->(_m) { raise "boom" }, timeout: 5)

      expect(described_class.watched).to be_nil
    end
  end
end
