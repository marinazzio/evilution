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

    it "registers the consolidated session tool" do
      tools = server.instance_variable_get(:@tools)

      expect(tools.keys).to include("evilution-session")
    end

    it "does not register the deprecated session-list/show/diff tools" do
      tools = server.instance_variable_get(:@tools)

      expect(tools.keys).not_to include("evilution-session-list")
      expect(tools.keys).not_to include("evilution-session-show")
      expect(tools.keys).not_to include("evilution-session-diff")
    end

    it "sets server name and version" do
      expect(server.instance_variable_get(:@name)).to eq("evilution")
      expect(server.instance_variable_get(:@version)).to eq(Evilution::VERSION)
    end
  end
end
