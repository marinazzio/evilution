# frozen_string_literal: true

require "json"
require "evilution/mcp/info_tool"
require "evilution/version"
require "evilution/feedback"

RSpec.describe Evilution::MCP::InfoTool do
  def call(**params)
    described_class.call(server_context: nil, **params)
  end

  def parse_response(response)
    JSON.parse(response.content.first[:text])
  end

  describe "class DSL" do
    it "is registered under the evilution-info tool name" do
      expect(described_class.name_value).to eq("evilution-info")
    end

    it "description includes the discovery-summary phrase" do
      expect(described_class.description).to include("Discover what evilution sees")
    end

    it "input_schema action enum matches VALID_ACTIONS" do
      enum = described_class.input_schema.to_h.dig(:properties, :action, :enum)
      expect(enum).to eq(described_class::VALID_ACTIONS)
    end
  end

  describe "VALID_ACTIONS" do
    it "lists the five supported actions" do
      expect(described_class::VALID_ACTIONS).to eq(%w[subjects tests environment statuses feedback])
    end

    it "is frozen" do
      expect(described_class::VALID_ACTIONS).to be_frozen
    end

    it "matches the dispatch ACTIONS table keys" do
      actions = described_class.send(:const_get, :ACTIONS)
      expect(actions.keys).to eq(described_class::VALID_ACTIONS)
    end
  end

  describe "action validation" do
    it "returns a config_error when action is missing" do
      response = call

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to eq("action is required")
    end

    it "returns a config_error when action is unknown" do
      response = call(action: "nope")

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to eq("unknown action: nope")
    end
  end

  describe "dispatch routing" do
    {
      "subjects" => Evilution::MCP::InfoTool::Actions::Subjects,
      "tests" => Evilution::MCP::InfoTool::Actions::Tests,
      "environment" => Evilution::MCP::InfoTool::Actions::Environment,
      "statuses" => Evilution::MCP::InfoTool::Actions::Statuses,
      "feedback" => Evilution::MCP::InfoTool::Actions::Feedback
    }.each do |action, klass|
      it "routes action '#{action}' to #{klass}" do
        expect(klass).to receive(:call)
        call(action: action, files: ["lib/foo.rb"])
      end
    end
  end

  describe "parse_files invocation" do
    before { allow(Evilution::MCP::InfoTool::Actions::Subjects).to receive(:call) }

    it "invokes RequestParser.parse_files when files is present" do
      expect(Evilution::MCP::InfoTool::RequestParser).to receive(:parse_files)
        .with(["lib/foo.rb"]).and_return([["lib/foo.rb"], {}])
      call(action: "subjects", files: ["lib/foo.rb"])
    end

    it "skips RequestParser.parse_files when files is absent" do
      expect(Evilution::MCP::InfoTool::RequestParser).not_to receive(:parse_files)
      call(action: "environment")
    end
  end

  describe "rescue orchestration" do
    it "maps Evilution::ConfigError raised by the action to a config_error response" do
      allow(Evilution::MCP::InfoTool::Actions::Environment).to receive(:call)
        .and_raise(Evilution::ConfigError.new("boom"))

      response = call(action: "environment")

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to eq("boom")
    end
  end
end

RSpec.describe Evilution::MCP::InfoTool, "feedback action registration" do
  it "lists feedback in VALID_ACTIONS" do
    expect(described_class::VALID_ACTIONS).to include("feedback")
  end

  it "dispatches action='feedback' to Actions::Feedback" do
    response = described_class.call(server_context: nil, action: "feedback")
    body = JSON.parse(response.content.first[:text])
    expect(body["discussion_url"]).to eq(Evilution::Feedback::DISCUSSION_URL)
  end
end
