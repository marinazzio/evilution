# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/base"

RSpec.describe Evilution::Config::Validators::Base do
  let(:subclass) do
    Class.new(described_class) do
      def self.call_coerce_symbol(value)
        coerce_symbol!(value, allowed: %i[a b], name: "test")
      end

      def self.call_coerce_positive_int(value)
        coerce_positive_int!(value, name: "test")
      end
    end
  end

  describe ".call" do
    it "raises NotImplementedError" do
      expect { described_class.call(1) }.to raise_error(NotImplementedError)
    end
  end

  describe "coerce_symbol!" do
    it "coerces string to allowed symbol" do
      expect(subclass.call_coerce_symbol("a")).to eq(:a)
    end

    it "returns allowed symbol unchanged" do
      expect(subclass.call_coerce_symbol(:b)).to eq(:b)
    end

    it "raises on nil with allowed list in message" do
      expect { subclass.call_coerce_symbol(nil) }
        .to raise_error(Evilution::ConfigError, "test must be a or b, got nil")
    end

    it "raises on disallowed value with symbol inspect" do
      expect { subclass.call_coerce_symbol(:z) }
        .to raise_error(Evilution::ConfigError, "test must be a or b, got :z")
    end

    it "raises ConfigError on Integer (not NoMethodError)" do
      expect { subclass.call_coerce_symbol(1) }
        .to raise_error(Evilution::ConfigError, "test must be a or b, got 1")
    end

    it "raises ConfigError on Boolean" do
      expect { subclass.call_coerce_symbol(true) }
        .to raise_error(Evilution::ConfigError, "test must be a or b, got true")
    end

    it "raises ConfigError on Array" do
      expect { subclass.call_coerce_symbol([:a]) }
        .to raise_error(Evilution::ConfigError, "test must be a or b, got [:a]")
    end
  end

  describe "coerce_positive_int!" do
    it "returns integer on positive int" do
      expect(subclass.call_coerce_positive_int(3)).to eq(3)
    end

    it "coerces string integer" do
      expect(subclass.call_coerce_positive_int("4")).to eq(4)
    end

    it "raises on Float" do
      expect { subclass.call_coerce_positive_int(1.5) }
        .to raise_error(Evilution::ConfigError, "test must be a positive integer, got 1.5")
    end

    it "raises on zero" do
      expect { subclass.call_coerce_positive_int(0) }
        .to raise_error(Evilution::ConfigError, "test must be a positive integer, got 0")
    end

    it "raises on non-numeric string" do
      expect { subclass.call_coerce_positive_int("abc") }
        .to raise_error(Evilution::ConfigError, 'test must be a positive integer, got "abc"')
    end

    it "raises on nil" do
      expect { subclass.call_coerce_positive_int(nil) }
        .to raise_error(Evilution::ConfigError, "test must be a positive integer, got nil")
    end
  end
end
