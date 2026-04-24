# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/isolation"

RSpec.describe Evilution::Config::Validators::Isolation do
  describe ".call" do
    %i[auto fork in_process].each do |value|
      it "returns #{value.inspect} for #{value.inspect}" do
        expect(described_class.call(value)).to eq(value)
      end
    end

    it "coerces string 'auto' to :auto" do
      expect(described_class.call("auto")).to eq(:auto)
    end

    it "raises on nil" do
      expect { described_class.call(nil) }
        .to raise_error(Evilution::ConfigError, "isolation must be auto, fork, or in_process, got nil")
    end

    it "raises on unknown value" do
      expect { described_class.call(:foo) }
        .to raise_error(Evilution::ConfigError, "isolation must be auto, fork, or in_process, got :foo")
    end

    it "raises ConfigError on Integer (not NoMethodError)" do
      expect { described_class.call(1) }
        .to raise_error(Evilution::ConfigError, "isolation must be auto, fork, or in_process, got 1")
    end

    it "raises ConfigError on Boolean" do
      expect { described_class.call(true) }
        .to raise_error(Evilution::ConfigError, "isolation must be auto, fork, or in_process, got true")
    end
  end
end
