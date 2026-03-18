# frozen_string_literal: true

require "evilution/isolation/in_process"

RSpec.describe Evilution::Isolation::InProcess, "memory reporting" do
  subject(:isolator) { described_class.new }

  let(:mutation) { double("Mutation", file_path: "lib/example.rb", original_source: "original") }

  before { allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000, 102_400) }

  describe "#call memory delta reporting" do
    it "includes memory_delta_kb in the result" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.memory_delta_kb).to eq(2400)
    end

    it "reports memory delta for passed tests" do
      test_command = ->(_m) { { passed: true } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.memory_delta_kb).to eq(2400)
    end

    it "returns nil memory_delta_kb on timeout" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(100_000, 100_000)

      test_command = lambda { |_m|
        sleep 10
        { passed: true }
      }

      result = isolator.call(mutation:, test_command:, timeout: 0.1)

      expect(result.memory_delta_kb).to be_nil
    end

    it "returns nil memory_delta_kb when RSS unavailable" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(nil)

      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.memory_delta_kb).to be_nil
    end

    it "reports memory delta on error" do
      test_command = ->(_m) { raise "boom" }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result).to be_error
      expect(result.memory_delta_kb).to eq(2400)
    end

    it "includes child_rss_kb from post-execution RSS" do
      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.child_rss_kb).to eq(102_400)
    end

    it "returns nil child_rss_kb when RSS unavailable" do
      allow(Evilution::Memory).to receive(:rss_kb).and_return(nil)

      test_command = ->(_m) { { passed: false } }

      result = isolator.call(mutation:, test_command:, timeout: 5)

      expect(result.child_rss_kb).to be_nil
    end
  end
end
