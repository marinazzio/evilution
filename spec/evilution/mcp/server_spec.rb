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

    it "registers the info tool" do
      tools = server.instance_variable_get(:@tools)

      expect(tools.keys).to include("evilution-info")
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

  # Protocol revision 2026-07-28 makes `resultType` mandatory on list results, but the mcp gem
  # negotiates that revision without emitting the field, so clients reject the whole list. See GH #1416.
  describe "list results" do
    def result_for(method, params = {})
      response = server.handle(
        { jsonrpc: "2.0", id: 1, method: method, params: params }
      )

      response[:result]
    end

    it "marks tools/list results complete" do
      expect(result_for("tools/list")[:resultType]).to eq("complete")
    end

    it "still returns the tools alongside the result type" do
      result = result_for("tools/list")

      expect(result[:tools].map { |tool| tool[:name] }).to include("evilution-mutate")
    end

    it "marks prompts/list results complete" do
      expect(result_for("prompts/list")[:resultType]).to eq("complete")
    end

    it "marks resources/list results complete" do
      expect(result_for("resources/list")[:resultType]).to eq("complete")
    end

    it "marks resources/templates/list results complete" do
      expect(result_for("resources/templates/list")[:resultType]).to eq("complete")
    end
  end
end
