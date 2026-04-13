# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../session/store"
require_relative "../session/diff"

require_relative "../mcp"

# @deprecated Superseded by {Evilution::MCP::SessionTool} (action: "diff") as of 0.22.8.
#   No longer registered with the MCP server; retained only for direct Ruby callers.
#   Will be removed entirely — tracked by EV-h8pw / GH #686.
class Evilution::MCP::SessionDiffTool < MCP::Tool
  tool_name "evilution-session-diff"
  description "DEPRECATED: use evilution-session with action: 'diff'. " \
              "Compare two mutation testing sessions and return the diff. " \
              "Shows new regressions, fixed mutations, and persistent survivors."
  input_schema(
    properties: {
      base: {
        type: "string",
        description: "Path to the base (older) session JSON file"
      },
      head: {
        type: "string",
        description: "Path to the head (newer) session JSON file"
      }
    }
  )

  class << self
    # rubocop:disable Lint/UnusedMethodArgument
    def call(server_context:, base: nil, head: nil)
      return error_response("config_error", "base is required") unless base
      return error_response("config_error", "head is required") unless head

      store = Evilution::Session::Store.new
      base_data = store.load(base)
      head_data = store.load(head)

      diff = Evilution::Session::Diff.new
      result = diff.call(base_data, head_data)

      ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(result.to_h) }])
    rescue Evilution::Error => e
      error_response("not_found", e.message)
    rescue ::JSON::ParserError => e
      error_response("parse_error", e.message)
    rescue SystemCallError => e
      error_response("runtime_error", e.message)
    end
    # rubocop:enable Lint/UnusedMethodArgument

    private

    def error_response(type, message)
      ::MCP::Tool::Response.new(
        [{ type: "text", text: ::JSON.generate({ error: { type: type, message: message } }) }],
        error: true
      )
    end
  end
end
