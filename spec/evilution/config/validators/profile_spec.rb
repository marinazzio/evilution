# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/profile"

RSpec.describe Evilution::Config::Validators::Profile do
  describe ".call" do
    %i[default strict].each do |value|
      it "returns #{value.inspect} for #{value.inspect}" do
        expect(described_class.call(value)).to eq(value)
      end
    end

    it "coerces string 'strict' to :strict" do
      expect(described_class.call("strict")).to eq(:strict)
    end

    it "coerces string 'default' to :default" do
      expect(described_class.call("default")).to eq(:default)
    end

    it "raises on nil" do
      expect { described_class.call(nil) }
        .to raise_error(Evilution::ConfigError, "profile must be default or strict, got nil")
    end

    it "raises on unknown symbol" do
      expect { described_class.call(:bogus) }
        .to raise_error(Evilution::ConfigError, "profile must be default or strict, got :bogus")
    end

    it "raises ConfigError on Integer (not NoMethodError)" do
      expect { described_class.call(1) }
        .to raise_error(Evilution::ConfigError, "profile must be default or strict, got 1")
    end

    it "raises ConfigError on Boolean" do
      expect { described_class.call(true) }
        .to raise_error(Evilution::ConfigError, "profile must be default or strict, got true")
    end
  end
end
