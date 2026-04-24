# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/example_targeting_cache"

RSpec.describe Evilution::Config::Validators::ExampleTargetingCache do
  describe ".call" do
    it "merges supplied values over DEFAULTS" do
      expect(described_class.call(max_files: 100))
        .to eq(max_files: 100, max_blocks: 10_000)
    end

    it "accepts symbol keys" do
      expect(described_class.call(max_blocks: 42)[:max_blocks]).to eq(42)
    end

    it "accepts string keys" do
      expect(described_class.call("max_blocks" => 42)[:max_blocks]).to eq(42)
    end

    it "raises when value is not a Hash" do
      expect { described_class.call(nil) }
        .to raise_error(Evilution::ConfigError,
                        "example_targeting_cache must be a Hash, got NilClass")
    end

    it "raises when key is not String or Symbol" do
      expect { described_class.call(1 => 10) }
        .to raise_error(Evilution::ConfigError,
                        "example_targeting_cache keys must be Strings or Symbols, got 1")
    end

    it "raises on non-positive max_files" do
      expect { described_class.call(max_files: 0) }
        .to raise_error(Evilution::ConfigError,
                        "example_targeting_cache.max_files must be a positive integer, got 0")
    end

    it "raises on non-integer max_blocks" do
      expect { described_class.call(max_blocks: "lots") }
        .to raise_error(Evilution::ConfigError,
                        'example_targeting_cache.max_blocks must be a positive integer, got "lots"')
    end
  end
end
