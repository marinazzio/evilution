# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../session/store"

module Evilution
  module MCP
    class SessionShowTool < ::MCP::Tool
      tool_name "evilution-session-show"
      description "Show full details of a past mutation testing session, " \
                  "including survived mutations with diffs."
      input_schema(
        properties: {
          path: {
            type: "string",
            description: "Absolute path to the session JSON file"
          }
        }
      )

      class << self
        # rubocop:disable Lint/UnusedMethodArgument
        def call(server_context:, path: nil)
          unless path
            return ::MCP::Tool::Response.new(
              [{ type: "text", text: ::JSON.generate({ error: { type: "config_error", message: "path is required" } }) }],
              error: true
            )
          end

          store = Session::Store.new
          data = store.load(path)
          ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(data) }])
        rescue Evilution::Error => e
          ::MCP::Tool::Response.new(
            [{ type: "text", text: ::JSON.generate({ error: { type: "not_found", message: e.message } }) }],
            error: true
          )
        end
        # rubocop:enable Lint/UnusedMethodArgument
      end
    end
  end
end
