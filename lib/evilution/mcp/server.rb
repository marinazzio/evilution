# frozen_string_literal: true

require "mcp"
require_relative "../version"
require_relative "mutate_tool"
require_relative "session_list_tool"
require_relative "session_show_tool"
require_relative "session_diff_tool"

class Evilution::MCP::Server
  def self.build
    ::MCP::Server.new(
      name: "evilution",
      version: Evilution::VERSION,
      tools: [MutateTool, SessionListTool, SessionShowTool, SessionDiffTool]
    )
  end
end
