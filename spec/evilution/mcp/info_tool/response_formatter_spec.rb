# frozen_string_literal: true

require "spec_helper"
require "json"
require "evilution/mcp/info_tool/response_formatter"

RSpec.describe Evilution::MCP::InfoTool::ResponseFormatter do
  def parse_body(response)
    JSON.parse(response.content.first[:text])
  end

  describe ".success" do
    it "wraps payload as a single text-content MCP response" do
      response = described_class.success("ok" => true)
      expect(response).to be_a(MCP::Tool::Response)
      expect(parse_body(response)).to eq("ok" => true)
    end

    it "does not mark the response as an error" do
      response = described_class.success("x" => 1)
      expect(response.error?).to be_falsey
    end
  end

  describe ".error" do
    it "wraps type + message into an MCP error response" do
      response = described_class.error("config_error", "missing")
      expect(response).to be_a(MCP::Tool::Response)
      expect(parse_body(response)).to eq("error" => { "type" => "config_error", "message" => "missing" })
    end

    it "sets error: true on the response" do
      response = described_class.error("parse_error", "bad")
      expect(response.error?).to be true
    end
  end

  describe ".error_for" do
    it "maps Evilution::ConfigError via ErrorMapper and builds error response" do
      response = described_class.error_for(Evilution::ConfigError.new("bad conf"))
      expect(parse_body(response)).to eq("error" => { "type" => "config_error", "message" => "bad conf" })
      expect(response.error?).to be true
    end

    it "maps Evilution::ParseError" do
      response = described_class.error_for(Evilution::ParseError.new("parse"))
      expect(parse_body(response)).to eq("error" => { "type" => "parse_error", "message" => "parse" })
    end

    it "maps generic Evilution::Error to runtime_error" do
      response = described_class.error_for(Evilution::Error.new("oops"))
      expect(parse_body(response)).to eq("error" => { "type" => "runtime_error", "message" => "oops" })
    end
  end
end
