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
              "or verifying that a fix killed the right mutant. " \
              "Contract: input schema, action enum, and output payloads are stable for the 1.x line; " \
              "see README \"MCP Server\" section for the full deprecation policy."
  input_schema(
    properties: {
      action: {
        type: "string",
        enum: %w[list show diff],
        description: "Which session operation to perform. 'list' browses history; 'show' displays one session; 'diff' compares two."
      },
      results_dir: {
        type: "string",
        description: "[list|show|diff] Session results directory (default: .evilution/results). " \
                     "For show/diff, acts as the containment root: path/base/head must resolve under this directory."
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

  LimitResult = Data.define(:limit, :error)
  private_constant :LimitResult

  class << self
    def call(server_context:, action: nil, results_dir: nil, limit: nil, path: nil, base: nil, head: nil)
      return error_response("config_error", "action is required") unless action
      return error_response("config_error", "unknown action: #{action}") unless VALID_ACTIONS.include?(action)

      case action
      when "list" then list_action(results_dir: results_dir, limit: limit)
      when "show" then show_action(path: path, results_dir: results_dir)
      when "diff" then diff_action(base: base, head: head, results_dir: results_dir)
      end
    end

    private

    def list_action(results_dir:, limit:)
      result = normalize_limit(limit)
      return error_response("config_error", result.error) if result.error

      store_opts = {}
      store_opts[:results_dir] = results_dir if results_dir
      store = Evilution::Session::Store.new(**store_opts)
      entries = store.list
      entries = entries.first(result.limit) unless result.limit.nil?

      sessions = entries.map { |e| e.transform_keys(&:to_s) }
      success_response("schema_version" => Evilution::MCP::CONTRACT_VERSION, "sessions" => sessions)
    end

    def normalize_limit(limit)
      return LimitResult.new(limit: nil, error: nil) if limit.nil?

      coerced = Integer(limit)
      return LimitResult.new(limit: nil, error: "limit must be a non-negative integer") if coerced.negative?

      LimitResult.new(limit: coerced, error: nil)
    rescue ArgumentError, TypeError
      LimitResult.new(limit: nil, error: "limit must be a non-negative integer")
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
      dir = results_dir || Evilution::Session::Store::DEFAULT_DIR
      validation = validate_diff_args(base, head, dir)
      return validation if validation

      result = load_and_diff(base, head, dir)
      payload = { "schema_version" => Evilution::MCP::CONTRACT_VERSION }.merge(result.to_h)
      success_response(payload)
    rescue Evilution::Error => e
      error_response("not_found", e.message)
    rescue ::JSON::ParserError => e
      error_response("parse_error", e.message)
    rescue SystemCallError => e
      error_response("runtime_error", e.message)
    end

    def validate_diff_args(base, head, dir)
      return error_response("config_error", "base is required") unless base
      return error_response("config_error", "head is required") unless head
      return error_response("config_error", "base must be under results directory") unless within?(base, dir)
      return error_response("config_error", "head must be under results directory") unless within?(head, dir)

      nil
    end

    def load_and_diff(base, head, dir)
      store = Evilution::Session::Store.new(results_dir: dir)
      Evilution::Session::Diff.new.call(store.load(base), store.load(head))
    end

    def within?(path, results_dir)
      resolved_root = canonical_path(results_dir)
      resolved_path = canonical_path(path)
      resolved_path == resolved_root || resolved_path.start_with?(resolved_root + File::SEPARATOR)
    end

    def canonical_path(path)
      File.realpath(path)
    rescue Errno::ENOENT
      File.expand_path(path)
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
