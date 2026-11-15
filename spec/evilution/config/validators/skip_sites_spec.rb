# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/skip_sites"

RSpec.describe Evilution::Config::Validators::SkipSites do
  describe ".call" do
    it "returns [] for nil" do
      expect(described_class.call(nil)).to eq([])
    end

    it "returns [] for false" do
      expect(described_class.call(false)).to eq([])
    end

    it "returns the preset names as symbols" do
      expect(described_class.call(%w[logging requires])).to eq(%i[logging requires])
    end

    it "accepts symbols" do
      expect(described_class.call(%i[error_messages])).to eq(%i[error_messages])
    end

    it "wraps a single name" do
      expect(described_class.call("debug_output")).to eq(%i[debug_output])
    end

    it "drops a name given twice" do
      expect(described_class.call(%w[logging logging])).to eq(%i[logging])
    end

    it "rejects an unknown preset, naming the known ones" do
      expect { described_class.call(%w[logging logs]) }
        .to raise_error(Evilution::ConfigError,
                        'skip_sites: unknown preset "logs" (known: logging, debug_output, error_messages, requires)')
    end

    it "rejects an unknown preset given as a symbol" do
      expect { described_class.call(%i[logs]) }
        .to raise_error(Evilution::ConfigError, /unknown preset :logs /)
    end

    it "rejects a value that is not a name" do
      expect { described_class.call([1]) }
        .to raise_error(Evilution::ConfigError,
                        "skip_sites: unknown preset 1 (known: logging, debug_output, error_messages, requires)")
    end
  end
end
