# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/warmup"

RSpec.describe Evilution::Config::Validators::Warmup do
  describe ".call" do
    %i[none rails].each do |value|
      it "returns #{value.inspect} for #{value.inspect}" do
        expect(described_class.call(value)).to eq(value)
      end
    end

    it "coerces string 'rails' to :rails" do
      expect(described_class.call("rails")).to eq(:rails)
    end

    it "treats false as :none, so `warmup: false` in YAML turns it off" do
      expect(described_class.call(false)).to eq(:none)
    end

    it "raises on nil" do
      expect { described_class.call(nil) }
        .to raise_error(Evilution::ConfigError, "warmup must be none or rails, got nil")
    end

    it "raises on an unknown value" do
      expect { described_class.call("sinatra") }
        .to raise_error(Evilution::ConfigError, "warmup must be none or rails, got :sinatra")
    end
  end
end
