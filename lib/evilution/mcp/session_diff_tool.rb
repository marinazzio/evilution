# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../session/store"

require_relative "../mcp"

class Evilution::MCP::SessionDiffTool < MCP::Tool
  tool_name "evilution-session-diff"
  description "Compare two mutation testing sessions and return the diff. " \
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

      ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(build_diff(base_data, head_data)) }])
    rescue Evilution::Error => e
      error_response("not_found", e.message)
    rescue ::JSON::ParserError => e
      error_response("parse_error", e.message)
    rescue SystemCallError => e
      error_response("runtime_error", e.message)
    end
    # rubocop:enable Lint/UnusedMethodArgument

    private

    def build_diff(base_data, head_data)
      base_survivors = base_data["survived"] || []
      head_survivors = head_data["survived"] || []

      base_keys = base_survivors.to_set { |m| mutation_key(m) }
      head_keys = head_survivors.to_set { |m| mutation_key(m) }

      {
        "summary" => build_summary_diff(base_data, head_data),
        "fixed" => base_survivors.reject { |m| head_keys.include?(mutation_key(m)) },
        "new_survivors" => head_survivors.reject { |m| base_keys.include?(mutation_key(m)) },
        "persistent" => head_survivors.select { |m| base_keys.include?(mutation_key(m)) }
      }
    end

    def build_summary_diff(base_data, head_data)
      base_summary = base_data["summary"] || {}
      head_summary = head_data["summary"] || {}
      base_score = base_summary["score"] || 0.0
      head_score = head_summary["score"] || 0.0

      {
        "base_score" => base_score,
        "head_score" => head_score,
        "score_delta" => (head_score - base_score).round(4),
        "base_survived" => base_summary["survived"] || 0,
        "head_survived" => head_summary["survived"] || 0
      }
    end

    def mutation_key(mutation)
      [mutation["operator"], mutation["file"], mutation["line"], mutation["subject"]]
    end

    def error_response(type, message)
      ::MCP::Tool::Response.new(
        [{ type: "text", text: ::JSON.generate({ error: { type: type, message: message } }) }],
        error: true
      )
    end
  end
end
