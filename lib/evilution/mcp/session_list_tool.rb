# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../session/store"

class Evilution::MCP::SessionListTool < MCP::Tool
  tool_name "evilution-session-list"
  description "List past mutation testing sessions with summary statistics. " \
              "Returns sessions in reverse chronological order."
  input_schema(
    properties: {
      results_dir: {
        type: "string",
        description: "Session results directory (default: .evilution/results)"
      },
      limit: {
        type: "integer",
        description: "Return only the N most recent sessions"
      }
    }
  )

  class << self
    # rubocop:disable Lint/UnusedMethodArgument
    def call(server_context:, results_dir: nil, limit: nil)
      store_opts = {}
      store_opts[:results_dir] = results_dir if results_dir
      store = Session::Store.new(**store_opts)
      entries = store.list
      entries = entries.first(limit) if limit

      payload = entries.map { |e| stringify_keys(e) }
      ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(payload) }])
    end
    # rubocop:enable Lint/UnusedMethodArgument

    private

    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end
  end
end
