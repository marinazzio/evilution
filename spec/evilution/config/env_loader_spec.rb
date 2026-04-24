# frozen_string_literal: true

require "spec_helper"
require "evilution/config"

RSpec.describe Evilution::Config::EnvLoader do
  describe ".load" do
    before { ENV.delete("EV_DISABLE_EXAMPLE_TARGETING") }

    it "returns {} when EV_DISABLE_EXAMPLE_TARGETING is unset" do
      expect(described_class.load).to eq({})
    end

    it "returns {} when EV_DISABLE_EXAMPLE_TARGETING is empty" do
      ENV["EV_DISABLE_EXAMPLE_TARGETING"] = ""
      expect(described_class.load).to eq({})
    end

    it "returns {} when EV_DISABLE_EXAMPLE_TARGETING is '0'" do
      ENV["EV_DISABLE_EXAMPLE_TARGETING"] = "0"
      expect(described_class.load).to eq({})
    end

    it "disables example targeting when EV_DISABLE_EXAMPLE_TARGETING is '1'" do
      ENV["EV_DISABLE_EXAMPLE_TARGETING"] = "1"
      expect(described_class.load).to eq(example_targeting: false)
    end

    it "disables example targeting for any non-zero, non-empty value" do
      ENV["EV_DISABLE_EXAMPLE_TARGETING"] = "yes"
      expect(described_class.load).to eq(example_targeting: false)
    end
  end
end
