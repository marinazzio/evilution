# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/example_targeting_fallback"

RSpec.describe Evilution::Config::Validators::ExampleTargetingFallback do
  describe ".call" do
    it "returns :full_file for :full_file" do
      expect(described_class.call(:full_file)).to eq(:full_file)
    end

    it "returns :unresolved for :unresolved" do
      expect(described_class.call(:unresolved)).to eq(:unresolved)
    end

    it "coerces string to symbol" do
      expect(described_class.call("full_file")).to eq(:full_file)
    end

    it "raises on nil" do
      expect { described_class.call(nil) }
        .to raise_error(Evilution::ConfigError,
                        "example_targeting_fallback must be full_file or unresolved, got nil")
    end

    it "raises on unknown symbol" do
      expect { described_class.call(:foo) }
        .to raise_error(Evilution::ConfigError,
                        "example_targeting_fallback must be full_file or unresolved, got :foo")
    end

    it "raises on non-string/symbol" do
      expect { described_class.call(123) }
        .to raise_error(Evilution::ConfigError,
                        "example_targeting_fallback must be full_file or unresolved, got 123")
    end
  end
end
