# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/jobs"

RSpec.describe Evilution::Config::Validators::Jobs do
  describe ".call" do
    it "returns the integer when >= 1" do
      expect(described_class.call(4)).to eq(4)
    end

    it "coerces string integer" do
      expect(described_class.call("2")).to eq(2)
    end

    it "raises on Float" do
      expect { described_class.call(2.5) }
        .to raise_error(Evilution::ConfigError, "jobs must be a positive integer, got 2.5")
    end

    it "raises on zero" do
      expect { described_class.call(0) }
        .to raise_error(Evilution::ConfigError, "jobs must be a positive integer, got 0")
    end

    it "raises on negative" do
      expect { described_class.call(-1) }
        .to raise_error(Evilution::ConfigError, "jobs must be a positive integer, got -1")
    end

    it "raises on non-numeric string" do
      expect { described_class.call("abc") }
        .to raise_error(Evilution::ConfigError, 'jobs must be a positive integer, got "abc"')
    end

    it "raises on nil" do
      expect { described_class.call(nil) }
        .to raise_error(Evilution::ConfigError, "jobs must be a positive integer, got nil")
    end
  end
end
