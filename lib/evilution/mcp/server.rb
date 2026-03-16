# frozen_string_literal: true

require "mcp"
require_relative "../version"
require_relative "mutate_tool"

module Evilution
  module MCP
    class Server
      def self.build
        ::MCP::Server.new(
          name: "evilution",
          version: Evilution::VERSION,
          tools: [MutateTool]
        )
      end
    end
  end
end
