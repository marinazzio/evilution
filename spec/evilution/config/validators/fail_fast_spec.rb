# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/fail_fast"

RSpec.describe Evilution::Config::Validators::FailFast do
  describe ".call" do
    it "returns nil for nil" do
      expect(described_class.call(nil)).to be_nil
    end

    it "returns integer for positive int" do
      expect(described_class.call(3)).to eq(3)
    end

    it "coerces string integer" do
      expect(described_class.call("5")).to eq(5)
    end

    it "raises on zero" do
      expect { described_class.call(0) }
        .to raise_error(Evilution::ConfigError, "fail_fast must be a positive integer, got 0")
    end

    it "raises on negative" do
      expect { described_class.call(-2) }
        .to raise_error(Evilution::ConfigError, "fail_fast must be a positive integer, got -2")
    end

    it "raises on non-numeric string" do
      expect { described_class.call("abc") }
        .to raise_error(Evilution::ConfigError, 'fail_fast must be a positive integer, got "abc"')
    end
  end
end
