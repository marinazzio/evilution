# frozen_string_literal: true

require "fileutils"
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
end
