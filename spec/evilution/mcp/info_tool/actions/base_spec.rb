# frozen_string_literal: true

require "spec_helper"
require "evilution/mcp/info_tool/actions/base"

RSpec.describe Evilution::MCP::InfoTool::Actions::Base do
  describe ".call" do
    it "raises NotImplementedError" do
      expect { described_class.call }.to raise_error(NotImplementedError)
    end
  end

  describe "private helpers" do
    let(:subclass) do
      Class.new(described_class) do
        def self.call_success(payload) = success(payload)
        def self.call_config_error(message) = config_error(message)
      end
    end

    it "success delegates to ResponseFormatter.success" do
      expect(Evilution::MCP::InfoTool::ResponseFormatter)
        .to receive(:success).with({ "ok" => 1 })
      subclass.call_success({ "ok" => 1 })
    end

    it "config_error builds a config_error response" do
      expect(Evilution::MCP::InfoTool::ResponseFormatter)
        .to receive(:error).with("config_error", "missing")
      subclass.call_config_error("missing")
    end
  end
end
