# frozen_string_literal: true

RSpec.describe Evilution::Result::NeutralReason do
  describe ".baseline_failure" do
    it "names the spec that was already failing" do
      reason = described_class.baseline_failure("spec/tally_spec.rb")

      expect([reason.kind, reason.detail]).to eq([:baseline_failure, "spec/tally_spec.rb"])
    end

    it "describes itself for a reader" do
      expect(described_class.baseline_failure("spec/tally_spec.rb").to_s)
        .to eq("baseline already failing (spec/tally_spec.rb)")
    end

    it "describes itself when the spec is unknown" do
      expect(described_class.baseline_failure(nil).to_s).to eq("baseline already failing")
    end
  end

  describe ".infra_error" do
    it "names the error class that ended the test process" do
      reason = described_class.infra_error("Timeout::Error")

      expect([reason.kind, reason.detail]).to eq([:infra_error, "Timeout::Error"])
    end

    it "describes itself for a reader" do
      expect(described_class.infra_error("Timeout::Error").to_s)
        .to eq("infrastructure error (Timeout::Error)")
    end
  end

  it "is comparable by value, so equal reasons group together" do
    expect(described_class.baseline_failure("a_spec.rb")).to eq(described_class.baseline_failure("a_spec.rb"))
  end
end
