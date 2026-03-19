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

    it "does not interfere with $LOADED_FEATURES" do
      features_before = $LOADED_FEATURES.dup

      test_command = ->(_m) { { passed: false } }
      isolator.call(mutation:, test_command:, timeout: 5)

      expect($LOADED_FEATURES).to eq(features_before)
    end
  end
end
