# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../config"
require_relative "../runner"
require_relative "../reporter/json"
require_relative "../reporter/suggestion"

require_relative "../mcp"

class Evilution::MCP::MutateTool < MCP::Tool
  tool_name "evilution-mutate"
  description "Run mutation testing on Ruby source files. " \
              "Use suggest_tests: true to get concrete test code (RSpec or Minitest) for surviving mutants."
  input_schema(
    properties: {
      files: {
        type: "array",
        items: { type: "string" },
        description: "Target files, supports line-range syntax (e.g. lib/foo.rb:15-30)"
      },
      target: {
        type: "string",
        description: "Only mutate the named method (e.g. Foo#bar)"
      },
      timeout: {
        type: "integer",
        description: "Per-mutation timeout in seconds (default: 30)"
      },
      jobs: {
        type: "integer",
        description: "Number of parallel workers (default: 1)"
      },
      fail_fast: {
        type: "integer",
        description: "Stop after N surviving mutants"
      },
      spec: {
        type: "array",
        items: { type: "string" },
        description: "Spec files to run (overrides auto-detection)"
      },
      suggest_tests: {
        type: "boolean",
        description: "When true, suggestions for survived mutants include concrete test code " \
                     "instead of static description text (default: false)"
      },
      incremental: {
        type: "boolean",
        description: "Cache killed/timeout results and skip re-running them on unchanged files. " \
                     "Set true when iterating on the same files to speed up repeat runs."
      },
      integration: {
        type: "string",
        enum: %w[rspec minitest],
        description: "Test integration to use (default: rspec)"
      },
      isolation: {
        type: "string",
        enum: %w[auto fork in_process],
        description: "Isolation strategy for mutation execution (default: auto)"
      },
      baseline: {
        type: "boolean",
        description: "Run a baseline test suite check before mutations (default: true). " \
                     "Set false to skip when you already know the suite is green."
      },
      save_session: {
        type: "boolean",
        description: "Save session results to .evilution/results/ for later inspection via evilution-session"
      },
      skip_config: {
        type: "boolean",
        description: "When true, ignore .evilution.yml / config/evilution.yml. " \
                     "MCP-specific overrides (JSON output, quiet mode, preload disabled) and explicit tool " \
                     "parameters still apply. Default: false — project config is loaded so the MCP run " \
                     "matches `evilution` CLI behavior."
      },
      verbosity: {
        type: "string",
        enum: %w[full summary minimal],
        description: "Response verbosity: full (all entries, diffs stripped from killed/neutral/equivalent), " \
                     "summary (omits killed/neutral/equivalent arrays; default), " \
                     "minimal (only summary + survived)"
      }
    }
  )

  class << self
    def call(server_context:, files: [], verbosity: nil, **opts)
      validate_opts!(opts)
      parsed_files, line_ranges = parse_files(Array(files))
      config_opts = build_config_opts(parsed_files, line_ranges, opts)
      config = Evilution::Config.new(**config_opts)
      suggest_tests = opts[:suggest_tests]
      on_result = build_streaming_callback(server_context, suggest_tests, config.integration)
      runner = Evilution::Runner.new(config: config, on_result: on_result)
      summary = runner.call
      report = Evilution::Reporter::JSON.new(suggest_tests: suggest_tests == true, integration: config.integration).call(summary)
      compact = trim_report(report, normalize_verbosity(verbosity))

      ::MCP::Tool::Response.new([{ type: "text", text: compact }])
    rescue Evilution::Error => e
      error_payload = build_error_payload(e)
      ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(error_payload) }], error: true)
    end

    VALID_VERBOSITIES = %w[full summary minimal].freeze
    PASSTHROUGH_KEYS = %i[target timeout jobs fail_fast suggest_tests incremental integration
                          isolation baseline save_session].freeze
    ALLOWED_OPT_KEYS = (PASSTHROUGH_KEYS + %i[spec skip_config]).freeze

    private

    def parse_files(raw_files)
      files = []
      ranges = {}

      raw_files.each do |arg|
        file, range_str = arg.split(":", 2)
        files << file
        next unless range_str

        ranges[file] = parse_line_range(range_str)
      end

      [files, ranges]
    end

    def parse_line_range(str)
      if str.include?("-")
        start_str, end_str = str.split("-", 2)
        start_line = Integer(start_str)
        end_line = end_str.empty? ? Float::INFINITY : Integer(end_str)
        start_line..end_line
      else
        line = Integer(str)
        line..line
      end
    rescue ArgumentError, TypeError
      raise Evilution::ParseError, "invalid line range: #{str.inspect}"
    end

    def validate_opts!(opts)
      unknown = opts.keys - ALLOWED_OPT_KEYS
      return if unknown.empty?

      raise Evilution::ParseError, "unknown parameters: #{unknown.join(", ")}"
    end

    def build_config_opts(files, line_ranges, params)
      # Preload is disabled for MCP invocations: `require`-ing Rails into the
      # long-lived MCP server would poison subsequent runs against other
      # projects. MCP users who want the speedup should use the CLI.
      opts = { target_files: files, line_ranges: line_ranges, format: :json, quiet: true, preload: false }
      opts[:skip_config_file] = true if params[:skip_config]
      opts[:spec_files] = params[:spec] if params[:spec]
      PASSTHROUGH_KEYS.each { |key| opts[key] = params[key] unless params[key].nil? }
      opts
    end

    def normalize_verbosity(value)
      normalized = value.to_s.strip.downcase
      normalized = "summary" if normalized.empty?
      return normalized if VALID_VERBOSITIES.include?(normalized)

      raise Evilution::ParseError, "invalid verbosity: #{value.inspect} (must be full, summary, or minimal)"
    end

    def trim_report(json_string, verbosity)
      data = ::JSON.parse(json_string)
      case verbosity
      when "full"
        strip_diffs(data, "killed")
        strip_diffs(data, "neutral")
        strip_diffs(data, "equivalent")
      when "summary"
        data.delete("killed")
        data.delete("neutral")
        data.delete("equivalent")
      when "minimal"
        data.delete("killed")
        data.delete("neutral")
        data.delete("equivalent")
        data.delete("timed_out")
        data.delete("errors")
      end
      ::JSON.generate(data)
    end

    def strip_diffs(data, key)
      return unless data[key]

      data[key].each { |entry| entry.delete("diff") }
    end

    def build_streaming_callback(server_context, suggest_tests, integration)
      return nil unless suggest_tests && server_context.respond_to?(:report_progress)

      suggestion = Evilution::Reporter::Suggestion.new(suggest_tests: true, integration: integration)
      survivor_index = 0

      proc do |result|
        next unless result.survived?

        begin
          survivor_index += 1
          detail = build_suggestion_detail(result.mutation, suggestion)
          server_context.report_progress(survivor_index, message: ::JSON.generate(detail))
        rescue StandardError # rubocop:disable Lint/SuppressedException
        end
      end
    end

    def build_suggestion_detail(mutation, suggestion)
      {
        operator: mutation.operator_name,
        file: mutation.file_path,
        line: mutation.line,
        subject: mutation.subject.name,
        diff: mutation.diff,
        suggestion: suggestion.suggestion_for(mutation)
      }
    end

    def build_error_payload(error)
      error_type = case error
                   when Evilution::ConfigError then "config_error"
                   when Evilution::ParseError then "parse_error"
                   else "runtime_error"
                   end

      payload = { type: error_type, message: error.message }
      payload[:file] = error.file if error.file
      { error: payload }
    end
  end
end
