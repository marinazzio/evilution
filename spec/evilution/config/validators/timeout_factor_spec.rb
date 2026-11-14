# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/timeout_factor"

RSpec.describe Evilution::Config::Validators::TimeoutFactor do
  describe ".call" do
    it "keeps a positive Integer as given" do
      expect(described_class.call(12)).to eql(12)
    end

    it "keeps a positive Float as given" do
      expect(described_class.call(0.5)).to eql(0.5)
    end

    it "parses a numeric string" do
      expect(described_class.call("1.5")).to eql(1.5)
    end

    [0, -2, 0.0, "abc", "", nil, false, Float::INFINITY, Float::NAN].each do |bad|
      it "raises on #{bad.inspect}" do
        expect { described_class.call(bad) }
          .to raise_error(Evilution::ConfigError, "timeout_factor must be a positive number, got #{bad.inspect}")
      end
    end
  end
end
