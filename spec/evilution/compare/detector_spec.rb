# frozen_string_literal: true

require "evilution/compare/detector"

RSpec.describe Evilution::Compare::Detector do
  describe ".call" do
    it "returns :mutant for JSON with subject_results" do
      expect(described_class.call({ "subject_results" => [] })).to eq(:mutant)
    end

    it "returns :evilution for JSON with summary and status buckets" do
      json = { "summary" => { "total" => 0 }, "killed" => [], "survived" => [] }
      expect(described_class.call(json)).to eq(:evilution)
    end

    it "returns :evilution when only one status bucket is present" do
      json = { "summary" => {}, "survived" => [] }
      expect(described_class.call(json)).to eq(:evilution)
    end

    it "raises InvalidInput on ambiguous shape (both markers present)" do
      json = { "subject_results" => [], "summary" => {}, "killed" => [] }
      expect { described_class.call(json) }
        .to raise_error(Evilution::Compare::InvalidInput, /ambiguous/)
    end

    it "raises InvalidInput when shape cannot be detected" do
      expect { described_class.call({ "unknown" => "stuff" }) }
        .to raise_error(Evilution::Compare::InvalidInput, /cannot detect/)
    end

    it "raises InvalidInput on non-Hash input" do
      expect { described_class.call([]) }
        .to raise_error(Evilution::Compare::InvalidInput, /Hash/)
    end
  end
end
