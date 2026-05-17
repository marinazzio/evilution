# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/ignore_patterns"

RSpec.describe Evilution::Config::Validators::IgnorePatterns do
  describe ".call" do
    it "returns [] for nil" do
      expect(described_class.call(nil)).to eq([])
    end

    it "returns the Array of strings" do
      expect(described_class.call(["call{name=info}"])).to eq(["call{name=info}"])
    end

    it "returns the same patterns array it validated" do
      patterns = ["call{name=info}", "call{name=debug}"]
      expect(described_class.call(patterns)).to eq(patterns)
    end

    it "wraps a single string in an array" do
      expect(described_class.call("call{name=info}")).to eq(["call{name=info}"])
    end

    it "raises on non-string element" do
      expect { described_class.call([123]) }
        .to raise_error(Evilution::ConfigError,
                        "ignore_patterns must be an array of strings, got Integer (123)")
    end

    it "inspects the rejected pattern in the message" do
      expect { described_class.call([Rational(1, 2)]) }
        .to raise_error(Evilution::ConfigError,
                        "ignore_patterns must be an array of strings, got Rational ((1/2))")
    end
  end
end
