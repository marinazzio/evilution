# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/spec_pattern"

RSpec.describe Evilution::Config::Validators::SpecPattern do
  describe ".call" do
    it "returns nil for nil" do
      expect(described_class.call(nil)).to be_nil
    end

    it "returns the String glob" do
      expect(described_class.call("spec/**/*_spec.rb")).to eq("spec/**/*_spec.rb")
    end

    it "raises on Array" do
      expect { described_class.call(["a"]) }
        .to raise_error(Evilution::ConfigError, "spec_pattern must be nil or a String glob, got Array")
    end

    it "raises on Integer" do
      expect { described_class.call(1) }
        .to raise_error(Evilution::ConfigError, "spec_pattern must be nil or a String glob, got Integer")
    end
  end
end
