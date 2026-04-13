# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../session/store"
require_relative "../session/diff"

require_relative "../mcp"

class Evilution::MCP::SessionTool < MCP::Tool
  tool_name "evilution-session"
  description "Inspect mutation testing history without re-running any tests. " \
              "One tool, three actions: " \
              "'list' browses saved sessions (reverse chronological), " \
              "'show' returns the full report for a session (summary, survived mutations with diffs, git context), " \
              "'diff' compares two sessions and surfaces new regressions, fixed mutations, persistent survivors, and score delta. " \
              "Prefer this over the CLI when auditing mutation score trends, triaging survivors, " \
              "or verifying that a fix killed the right mutant."
  input_schema(
    properties: {
      action: {
        type: "string",
        enum: %w[list show diff],
        description: "Which session operation to perform. 'list' browses history; 'show' displays one session; 'diff' compares two."
      },
      results_dir: {
        type: "string",
        description: "[list] Session results directory (default: .evilution/results)"
      },
      limit: {
        type: "integer",
        description: "[list] Return only the N most recent sessions"
      },
      path: {
        type: "string",
        description: "[show] Path to a session JSON file (as returned by action=list); must be under results_dir"
      },
      base: {
        type: "string",
        description: "[diff] Path to the base (older) session JSON file; must be under results_dir"
      },
      head: {
        type: "string",
        description: "[diff] Path to the head (newer) session JSON file; must be under results_dir"
      }
    },
    required: ["action"]
  )

  VALID_ACTIONS = %w[list show diff].freeze

  class << self
    # rubocop:disable Lint/UnusedMethodArgument
    def call(server_context:, action: nil, results_dir: nil, limit: nil, path: nil, base: nil, head: nil)
      return error_response("config_error", "action is required") unless action
      return error_response("config_error", "unknown action: #{action}") unless VALID_ACTIONS.include?(action)

      case action
      when "list" then list_action(results_dir: results_dir, limit: limit)
      when "show" then show_action(path: path, results_dir: results_dir)
      when "diff" then diff_action(base: base, head: head, results_dir: results_dir)
      end
    end
    # rubocop:enable Lint/UnusedMethodArgument

    private

    def list_action(results_dir:, limit:)
      normalized_limit, limit_error = normalize_limit(limit)
      return error_response("config_error", limit_error) if limit_error

      store_opts = {}
      store_opts[:results_dir] = results_dir if results_dir
      store = Evilution::Session::Store.new(**store_opts)
      entries = store.list
      entries = entries.first(normalized_limit) unless normalized_limit.nil?

      payload = entries.map { |e| e.transform_keys(&:to_s) }
      success_response(payload)
    end

    def normalize_limit(limit)
      return [nil, nil] if limit.nil?

      coerced = Integer(limit)
      return [nil, "limit must be a non-negative integer"] if coerced.negative?

      [coerced, nil]
    rescue ArgumentError, TypeError
      [nil, "limit must be a non-negative integer"]
    end

    def show_action(path:, results_dir:)
      return error_response("config_error", "path is required") unless path

      dir = results_dir || Evilution::Session::Store::DEFAULT_DIR
      return error_response("config_error", "path must be under results directory") unless within?(path, dir)

      store = Evilution::Session::Store.new(results_dir: dir)
      data = store.load(path)
      success_response(data)
    rescue Evilution::Error => e
      error_response("not_found", e.message)
    rescue ::JSON::ParserError => e
      error_response("parse_error", e.message)
    rescue SystemCallError => e
      error_response("runtime_error", e.message)
    end

    def diff_action(base:, head:, results_dir:)
      return error_response("config_error", "base is required") unless base
      return error_response("config_error", "head is required") unless head

      dir = results_dir || Evilution::Session::Store::DEFAULT_DIR
      return error_response("config_error", "base must be under results directory") unless within?(base, dir)
      return error_response("config_error", "head must be under results directory") unless within?(head, dir)

      store = Evilution::Session::Store.new(results_dir: dir)
      base_data = store.load(base)
      head_data = store.load(head)

      diff = Evilution::Session::Diff.new
      result = diff.call(base_data, head_data)
      success_response(result.to_h)
    rescue Evilution::Error => e
      error_response("not_found", e.message)
    rescue ::JSON::ParserError => e
      error_response("parse_error", e.message)
    rescue SystemCallError => e
      error_response("runtime_error", e.message)
    end

    def within?(path, results_dir)
      resolved_root = File.expand_path(results_dir) + File::SEPARATOR
      resolved_path = File.expand_path(path)
      resolved_path.start_with?(resolved_root)
    end

    def success_response(payload)
      ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(payload) }])
    end

    def error_response(type, message)
      ::MCP::Tool::Response.new(
        [{ type: "text", text: ::JSON.generate({ error: { type: type, message: message } }) }],
        error: true
      )
    end
  end
end
