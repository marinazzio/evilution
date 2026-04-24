# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/hooks"

RSpec.describe Evilution::Config::Validators::Hooks do
  describe ".call" do
    it "returns {} for nil" do
      expect(described_class.call(nil)).to eq({})
    end

    it "returns the Hash unchanged" do
      hooks = { worker_process_start: "path/to/hook.rb" }
      expect(described_class.call(hooks)).to eq(hooks)
    end

    it "raises on Array" do
      expect { described_class.call(["a"]) }
        .to raise_error(Evilution::ConfigError, "hooks must be a mapping of event names to file paths, got Array")
    end

    it "raises on String" do
      expect { described_class.call("oops") }
        .to raise_error(Evilution::ConfigError, "hooks must be a mapping of event names to file paths, got String")
    end
  end
end
