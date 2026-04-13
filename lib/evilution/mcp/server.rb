# frozen_string_literal: true

require "mcp"
require_relative "../version"
require_relative "mutate_tool"
require_relative "session_tool"

require_relative "../mcp"

class Evilution::MCP::Server
  def self.build
    ::MCP::Server.new(
      name: "evilution",
      version: Evilution::VERSION,
      tools: [Evilution::MCP::MutateTool, Evilution::MCP::SessionTool]
    )
  end
end
