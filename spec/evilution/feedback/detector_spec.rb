# frozen_string_literal: true

require "evilution/feedback/detector"

RSpec.describe Evilution::Feedback::Detector do
  unless defined?(Summary)
    Summary = Struct.new(:errors, :unparseable, :unresolved, keyword_init: true) do
      def initialize(errors: 0, unparseable: 0, unresolved: 0)
        super
      end
    end
  end

  describe ".friction?" do
    it "returns false for nil" do
      expect(described_class.friction?(nil)).to be false
    end

    it "returns false when all friction buckets are zero" do
      expect(described_class.friction?(Summary.new)).to be false
    end

    it "returns true when errors > 0" do
      expect(described_class.friction?(Summary.new(errors: 1))).to be true
    end

    it "returns true when unparseable > 0" do
      expect(described_class.friction?(Summary.new(unparseable: 1))).to be true
    end

    it "returns true when unresolved > 0" do
      expect(described_class.friction?(Summary.new(unresolved: 1))).to be true
    end
  end
end
