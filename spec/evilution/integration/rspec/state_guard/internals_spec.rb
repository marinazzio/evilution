# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec/state_guard/internals"

RSpec.describe Evilution::Integration::RSpec::StateGuard::Internals do
  describe ".world_ivar" do
    it "returns the value when ivar is defined on RSpec.world" do
      RSpec.world.instance_variable_set(:@evilution_test_ivar, [:probe])
      expect(described_class.world_ivar(:@evilution_test_ivar)).to eq([:probe])
    ensure
      RSpec.world.remove_instance_variable(:@evilution_test_ivar) if RSpec.world.instance_variable_defined?(:@evilution_test_ivar)
    end

    it "returns nil when ivar is not defined" do
      expect(described_class.world_ivar(:@definitely_not_set)).to be_nil
    end
  end

  describe ".config_ivar" do
    it "returns the value when ivar is defined on RSpec.configuration" do
      RSpec.configuration.instance_variable_set(:@evilution_cfg_test, 42)
      expect(described_class.config_ivar(:@evilution_cfg_test)).to eq(42)
    ensure
      if RSpec.configuration.instance_variable_defined?(:@evilution_cfg_test)
        RSpec.configuration.remove_instance_variable(:@evilution_cfg_test)
      end
    end

    it "returns nil when ivar is not defined" do
      expect(described_class.config_ivar(:@definitely_not_set)).to be_nil
    end
  end
end
