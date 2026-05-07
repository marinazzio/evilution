# frozen_string_literal: true

require "evilution/mcp"

RSpec.describe Evilution::MCP do
  describe "CONTRACT_VERSION" do
    it "is defined as an Integer" do
      expect(described_class::CONTRACT_VERSION).to be_a(Integer)
    end

    it "is 1 (initial 1.0 contract)" do
      expect(described_class::CONTRACT_VERSION).to eq(1)
    end

    it "is independent of Session::Schema::CURRENT_VERSION (different surfaces, may diverge)" do
      require "evilution/session/schema"
      # Today they happen to be equal; the test just asserts both constants exist
      # so a future MCP contract bump (without a session-JSON bump) doesn't break
      # this spec — it only documents the dual identity.
      expect(described_class::CONTRACT_VERSION).to be_a(Integer)
      expect(Evilution::Session::Schema::CURRENT_VERSION).to be_a(Integer)
    end
  end
end
