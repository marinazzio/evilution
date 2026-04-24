# frozen_string_literal: true

require "spec_helper"
require "evilution/config"

RSpec.describe Evilution::Config::Sources do
  describe ".merge" do
    before { ENV.delete("EV_DISABLE_EXAMPLE_TARGETING") }

    it "returns DEFAULTS when no file, no env, no explicit" do
      allow(Evilution::Config::FileLoader).to receive(:load).and_return({})
      expect(described_class.merge(explicit: {}, skip_file: false))
        .to include(timeout: 30, jobs: 1, integration: :rspec)
    end

    it "skips file when skip_file: true" do
      expect(Evilution::Config::FileLoader).not_to receive(:load)
      described_class.merge(explicit: {}, skip_file: true)
    end

    it "applies precedence: DEFAULTS < file < env < explicit" do
      allow(Evilution::Config::FileLoader).to receive(:load)
        .and_return(timeout: 60, jobs: 4, example_targeting: true)
      ENV["EV_DISABLE_EXAMPLE_TARGETING"] = "1"

      merged = described_class.merge(explicit: { jobs: 8 }, skip_file: false)

      expect(merged[:timeout]).to eq(60)
      expect(merged[:example_targeting]).to eq(false)
      expect(merged[:jobs]).to eq(8)
    end
  end
end
