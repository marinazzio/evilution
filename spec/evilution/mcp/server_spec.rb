# frozen_string_literal: true

require "evilution/mcp/server"

RSpec.describe Evilution::MCP::Server do
  subject(:server) { described_class.build }

  describe ".build" do
    it "returns an MCP::Server instance" do
      expect(server).to be_a(MCP::Server)
    end

    it "registers the mutate tool" do
      tools = server.instance_variable_get(:@tools)

      expect(tools.keys).to include("evilution-mutate")
    end

    it "sets server name and version" do
      expect(server.instance_variable_get(:@name)).to eq("evilution")
      expect(server.instance_variable_get(:@version)).to eq(Evilution::VERSION)
    end
  end
end
