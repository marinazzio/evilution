# frozen_string_literal: true

require_relative "../../support/fresh_ruby_process"

# Each MCP entry point is required first in a fresh Ruby process where
# nothing has defined the Evilution namespace yet, so each must require what
# defines it before opening a class or module inside it.
RSpec.describe "Evilution::MCP load order" do
  include FreshRubyProcess

  {
    "evilution/mcp" => "Evilution::MCP",
    "evilution/mcp/server" => "Evilution::MCP::Server",
    "evilution/mcp/complete_result_server" => "Evilution::MCP::CompleteResultServer",
    "evilution/mcp/mutate_tool" => "Evilution::MCP::MutateTool",
    "evilution/mcp/session_tool" => "Evilution::MCP::SessionTool"
  }.each do |feature, constant|
    it "loads #{feature} on its own and defines #{constant}" do
      stdout, stderr, status = require_in_fresh_ruby(feature, constant)

      expect([stdout, stderr, status.success?]).to eq(["nil #{constant}", "", true])
    end
  end
end
