# frozen_string_literal: true

require "evilution/mcp/mutate_tool"

RSpec.describe Evilution::MCP::MutateTool::ErrorPayload do
  describe ".build" do
    it "maps ConfigError to config_error" do
      payload = described_class.build(Evilution::ConfigError.new("bad yml"))
      expect(payload).to eq(error: { type: "config_error", message: "bad yml" })
    end

    it "maps ParseError to parse_error" do
      payload = described_class.build(Evilution::ParseError.new("bad range"))
      expect(payload).to eq(error: { type: "parse_error", message: "bad range" })
    end

    it "maps any other Evilution::Error to runtime_error" do
      payload = described_class.build(Evilution::Error.new("boom"))
      expect(payload).to eq(error: { type: "runtime_error", message: "boom" })
    end

    it "includes file when the error exposes one" do
      error = Evilution::ParseError.new("bad", file: "lib/foo.rb")
      payload = described_class.build(error)
      expect(payload).to eq(error: { type: "parse_error", message: "bad", file: "lib/foo.rb" })
    end

    it "omits file when nil" do
      payload = described_class.build(Evilution::ParseError.new("bad"))
      expect(payload[:error]).not_to have_key(:file)
    end
  end
end
