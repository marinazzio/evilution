# frozen_string_literal: true

require "mcp"
require_relative "../version"
require_relative "mutate_tool"
require_relative "session_list_tool"
require_relative "session_show_tool"

module Evilution
  module MCP
    class Server
      def self.build
        ::MCP::Server.new(
          name: "evilution",
          version: Evilution::VERSION,
          tools: [MutateTool, SessionListTool, SessionShowTool]
        )
      end
    end
  end
end
