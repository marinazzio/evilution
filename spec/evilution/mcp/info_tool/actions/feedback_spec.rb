# frozen_string_literal: true

require "json"
require "evilution/mcp/info_tool/actions/feedback"
require "evilution/feedback"
require "evilution/feedback/messages"
require "evilution/version"

RSpec.describe Evilution::MCP::InfoTool::Actions::Feedback do
  describe ".call" do
    let(:response) { described_class.call }
    let(:body) { JSON.parse(response.content.first[:text]) }

    it "returns the discussion URL" do
      expect(body["discussion_url"]).to eq(Evilution::Feedback::DISCUSSION_URL)
    end

    it "returns the current evilution version" do
      expect(body["version"]).to eq(Evilution::VERSION)
    end

    it "returns guidance text mentioning consent" do
      expect(body["guidance_for_agent"]).to match(/consent|permission|approval/i)
    end

    it "returns guidance text mentioning privacy" do
      expect(body["guidance_for_agent"]).to match(/secret|token|env|path/i)
    end
  end
end
