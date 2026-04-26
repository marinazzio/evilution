# frozen_string_literal: true

require "evilution/mcp/mutate_tool"
require "evilution/feedback"
require "evilution/feedback/messages"

RSpec.describe Evilution::MCP::MutateTool::ErrorPayload do
  describe ".build" do
    it "maps ConfigError to config_error" do
      payload = described_class.build(Evilution::ConfigError.new("bad yml"))
      expect(payload[:error]).to eq(type: "config_error", message: "bad yml")
    end

    it "maps ParseError to parse_error" do
      payload = described_class.build(Evilution::ParseError.new("bad range"))
      expect(payload[:error]).to eq(type: "parse_error", message: "bad range")
    end

    it "maps any other Evilution::Error to runtime_error" do
      payload = described_class.build(Evilution::Error.new("boom"))
      expect(payload[:error]).to eq(type: "runtime_error", message: "boom")
    end

    it "includes file when the error exposes one" do
      error = Evilution::ParseError.new("bad", file: "lib/foo.rb")
      payload = described_class.build(error)
      expect(payload[:error]).to eq(type: "parse_error", message: "bad", file: "lib/foo.rb")
    end

    it "omits file when nil" do
      payload = described_class.build(Evilution::ParseError.new("bad"))
      expect(payload[:error]).not_to have_key(:file)
    end
  end
end

RSpec.describe Evilution::MCP::MutateTool::ErrorPayload, "feedback embedding" do
  describe ".build" do
    it "embeds feedback_url at top level" do
      payload = described_class.build(Evilution::Error.new("boom"))
      expect(payload[:feedback_url]).to eq(Evilution::Feedback::DISCUSSION_URL)
    end

    it "embeds feedback_hint at top level" do
      payload = described_class.build(Evilution::Error.new("boom"))
      expect(payload[:feedback_hint]).to eq(Evilution::Feedback::Messages.mcp_hint)
    end

    it "still preserves the existing :error key with its type and message" do
      payload = described_class.build(Evilution::ConfigError.new("nope"))
      expect(payload[:error]).to include(type: "config_error", message: "nope")
    end
  end
end
