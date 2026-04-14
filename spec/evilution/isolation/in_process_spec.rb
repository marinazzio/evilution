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
  end
end
