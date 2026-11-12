# frozen_string_literal: true

require "evilution/integration/stop_policy"
require "evilution/integration/known_failures"

RSpec.describe Evilution::Integration::StopPolicy do
  let(:known) { Evilution::Integration::KnownFailures.new(%w[known]) }
  let(:enabled) { true }
  let(:infra_class) do
    Class.new(StandardError) { def self.name = "SQLite3::BusyException" }
  end

  subject(:policy) { described_class.new(enabled: enabled, known_failures: known) }

  describe "#decisive?" do
    it "is true for an assertion failure of an unknown test" do
      expect(policy.decisive?(id: "new")).to be true
    end

    it "is true for a crash that is not infrastructure" do
      expect(policy.decisive?(id: "new", exception: NoMethodError.new("x"))).to be true
    end

    it "is false for an infrastructure crash" do
      expect(policy.decisive?(id: "new", exception: infra_class.new("busy"))).to be false
    end

    it "is false for a test the baseline already saw failing" do
      expect(policy.decisive?(id: "known")).to be false
    end

    it "is false for a known test crashing on something that is not infrastructure" do
      expect(policy.decisive?(id: "known", exception: NoMethodError.new("x"))).to be false
    end
  end

  describe "#record" do
    context "when disabled" do
      let(:enabled) { false }

      it "never stops" do
        expect(policy.record(id: "new")).to be false
        expect(policy).not_to be_stopped
      end
    end

    it "does not stop on a failure that is not decisive" do
      expect(policy.record(id: "known")).to be false
      expect(policy).not_to be_stopped
    end

    it "stops on the first decisive failure" do
      expect(policy.record(id: "new")).to be true
      expect(policy).to be_stopped
    end

    it "is cleared by reset" do
      policy.record(id: "new")
      policy.reset
      expect(policy).not_to be_stopped
    end
  end

  describe "DISABLED" do
    it "is frozen and never stops, however often it is used" do
      disabled = described_class::DISABLED
      expect(disabled).to be_frozen
      2.times do
        expect(disabled.record(id: "new")).to be false
        disabled.reset
        expect(disabled).not_to be_stopped
      end
    end
  end
end
