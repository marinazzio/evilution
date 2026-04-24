# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/integration"

RSpec.describe Evilution::Config::Validators::Integration do
  describe ".call" do
    it "returns :rspec for :rspec" do
      expect(described_class.call(:rspec)).to eq(:rspec)
    end

    it "returns :minitest for :minitest" do
      expect(described_class.call(:minitest)).to eq(:minitest)
    end

    it "coerces string 'rspec' to :rspec" do
      expect(described_class.call("rspec")).to eq(:rspec)
    end

    it "raises on nil" do
      expect { described_class.call(nil) }
        .to raise_error(Evilution::ConfigError, "integration must be rspec or minitest, got nil")
    end

    it "raises on unknown value" do
      expect { described_class.call(:foo) }
        .to raise_error(Evilution::ConfigError, "integration must be rspec or minitest, got :foo")
    end
  end
end
