# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../session/store"

require_relative "../mcp"

# @deprecated Superseded by {Evilution::MCP::SessionTool} (action: "show") as of 0.22.8.
#   No longer registered with the MCP server; retained only for direct Ruby callers.
#   Will be removed entirely — tracked by EV-h8pw / GH #686.
class Evilution::MCP::SessionShowTool < MCP::Tool
  tool_name "evilution-session-show"
  description "DEPRECATED: use evilution-session with action: 'show'. " \
              "Show full details of a past mutation testing session, " \
              "including survived mutations with diffs."
  input_schema(
    properties: {
      path: {
        type: "string",
        description: "Path to the session JSON file (as returned by evilution-session-list)"
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

      store = Evilution::Session::Store.new
      data = store.load(path)
      ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(data) }])
    rescue Evilution::Error => e
      ::MCP::Tool::Response.new(
        [{ type: "text", text: ::JSON.generate({ error: { type: "not_found", message: e.message } }) }],
        error: true
      )
    rescue ::JSON::ParserError => e
      ::MCP::Tool::Response.new(
        [{ type: "text", text: ::JSON.generate({ error: { type: "parse_error", message: e.message } }) }],
        error: true
      )
    rescue SystemCallError => e
      ::MCP::Tool::Response.new(
        [{ type: "text", text: ::JSON.generate({ error: { type: "runtime_error", message: e.message } }) }],
        error: true
      )
    end
    # rubocop:enable Lint/UnusedMethodArgument
  end
end
