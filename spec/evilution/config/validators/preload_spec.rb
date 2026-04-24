# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/preload"

RSpec.describe Evilution::Config::Validators::Preload do
  describe ".call" do
    it "returns nil for nil" do
      expect(described_class.call(nil)).to be_nil
    end

    it "returns false for false" do
      expect(described_class.call(false)).to eq(false)
    end

    it "returns the String path" do
      expect(described_class.call("spec/helper.rb")).to eq("spec/helper.rb")
    end

    it "raises on Integer" do
      expect { described_class.call(1) }
        .to raise_error(Evilution::ConfigError, "preload must be nil, false, or a String path, got 1")
    end

    it "raises on true" do
      expect { described_class.call(true) }
        .to raise_error(Evilution::ConfigError, "preload must be nil, false, or a String path, got true")
    end
  end
end
