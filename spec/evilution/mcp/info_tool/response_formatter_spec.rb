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
      expect(parse_body(response)).to include("ok" => true)
    end

    it "does not mark the response as an error" do
      response = described_class.success("x" => 1)
      expect(response.error?).to be_falsey
    end

    it "injects schema_version equal to MCP::CONTRACT_VERSION" do
      response = described_class.success("ok" => true)
      expect(parse_body(response)["schema_version"]).to eq(Evilution::MCP::CONTRACT_VERSION)
    end

    it "places schema_version first in the JSON output for discoverability" do
      response = described_class.success("ok" => true, "extra" => 1)
      keys = parse_body(response).keys
      expect(keys.first).to eq("schema_version")
    end

    it "does not overwrite an existing schema_version key in the payload" do
      response = described_class.success("schema_version" => 99, "ok" => true)
      expect(parse_body(response)["schema_version"]).to eq(99)
    end

    it "leaves a non-Hash payload untouched instead of injecting a schema_version" do
      response = described_class.success("plain string payload")
      expect(parse_body(response)).to eq("plain string payload")
    end

    it "treats a payload carrying a symbol schema_version key as already versioned" do
      payload = { schema_version: 42, ok: true }
      result = described_class.send(:inject_schema_version, payload)
      expect(result).to equal(payload)
      expect(result).not_to have_key("schema_version")
    end

    it "returns a non-Hash payload unchanged from inject_schema_version" do
      result = described_class.send(:inject_schema_version, "raw")
      expect(result).to eq("raw")
    end

    # EV-04sc / GH #1300: Line 16 — `type: "text"` mutated to `type: ""`. MCP
    # clients dispatch on the type field; the literal "text" must appear.
    it "tags the response content element with type: 'text' (not empty string)" do
      response = described_class.success("ok" => true)

      expect(response.content.first[:type]).to eq("text")
    end
  end

  describe ".error (content element shape)" do
    # EV-04sc / GH #1300: Line 29 — `type: "text"` mutated to `type: ""`.
    it "tags the error content element with type: 'text' (not empty string)" do
      response = described_class.error("config_error", "missing")

      expect(response.content.first[:type]).to eq("text")
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

    # EV-04sc / GH #1300: Line 35 — `error(type, exception.message)` mutated to
    # `error(type, exception)`. The serialized message must be the String
    # message, not a serialization of the Exception object itself.
    it "passes the exception's #message string (not the exception object) to error" do
      exception = Evilution::Error.new("specific-evilution-marker")

      response = described_class.error_for(exception)
      body = parse_body(response)

      expect(body["error"]["message"]).to eq("specific-evilution-marker")
      expect(body["error"]["message"]).to be_a(String)
    end
  end
end
