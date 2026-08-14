# frozen_string_literal: true

require "evilution/mcp/complete_result_server"

RSpec.describe Evilution::MCP::CompleteResultServer do
  subject(:server) do
    described_class.new(name: "evilution-test", version: "0.0.1", tools: [first_tool, second_tool])
  end

  let(:first_tool) do
    MCP::Tool.define(name: "first-tool", description: "First") { MCP::Tool::Response.new([]) }
  end

  let(:second_tool) do
    MCP::Tool.define(name: "second-tool", description: "Second") { MCP::Tool::Response.new([]) }
  end

  def result_for(method, params = {})
    server.handle({ jsonrpc: "2.0", id: 1, method: method, params: params })[:result]
  end

  describe "#handle" do
    it "adds the result type to tools/list" do
      expect(result_for("tools/list")[:resultType]).to eq("complete")
    end

    it "adds the result type to prompts/list" do
      expect(result_for("prompts/list")[:resultType]).to eq("complete")
    end

    it "adds the result type to resources/list" do
      expect(result_for("resources/list")[:resultType]).to eq("complete")
    end

    it "adds the result type to resources/templates/list" do
      expect(result_for("resources/templates/list")[:resultType]).to eq("complete")
    end

    it "keeps every listed tool" do
      expect(result_for("tools/list")[:tools].map { |tool| tool[:name] })
        .to contain_exactly("first-tool", "second-tool")
    end

    it "keeps the pagination cursor of a partial page" do
      server.page_size = 1

      expect(result_for("tools/list")).to include(:nextCursor)
    end

    it "marks a partial page complete as well" do
      server.page_size = 1

      expect(result_for("tools/list")[:resultType]).to eq("complete")
    end

    it "leaves non-list results untouched" do
      expect(result_for("ping")).not_to include(:resultType)
    end
  end
end
