# frozen_string_literal: true

require "spec_helper"
require "evilution/mcp/info_tool/error_mapper"

RSpec.describe Evilution::MCP::InfoTool::ErrorMapper do
  describe ".type_for" do
    it "returns 'config_error' for Evilution::ConfigError" do
      expect(described_class.type_for(Evilution::ConfigError.new("oops")))
        .to eq("config_error")
    end

    it "returns 'parse_error' for Evilution::ParseError" do
      expect(described_class.type_for(Evilution::ParseError.new("bad"))).to eq("parse_error")
    end

    it "returns 'runtime_error' for any other Evilution::Error" do
      expect(described_class.type_for(Evilution::Error.new("X"))).to eq("runtime_error")
    end

    it "returns 'runtime_error' for Evilution::Error subclass not otherwise matched" do
      stub_const("Evilution::OtherError", Class.new(Evilution::Error))
      expect(described_class.type_for(Evilution::OtherError.new("X"))).to eq("runtime_error")
    end
  end
end
