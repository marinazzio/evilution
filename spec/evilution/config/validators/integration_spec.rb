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

    it "returns :test_unit for :test_unit" do
      expect(described_class.call(:test_unit)).to eq(:test_unit)
    end

    it "coerces string 'rspec' to :rspec" do
      expect(described_class.call("rspec")).to eq(:rspec)
    end

    it "coerces string 'test-unit' (hyphenated, gem-name form) to :test_unit" do
      expect(described_class.call("test-unit")).to eq(:test_unit)
    end

    it "coerces string 'test_unit' (underscored) to :test_unit" do
      expect(described_class.call("test_unit")).to eq(:test_unit)
    end

    it "raises on nil" do
      expect { described_class.call(nil) }
        .to raise_error(Evilution::ConfigError, /integration must be.*got nil/)
    end

    it "raises on unknown value" do
      expect { described_class.call(:foo) }
        .to raise_error(Evilution::ConfigError, /integration must be.*got :foo/)
    end

    it "raises ConfigError on Integer (not NoMethodError)" do
      expect { described_class.call(1) }
        .to raise_error(Evilution::ConfigError, /integration must be.*got 1/)
    end
  end
end
