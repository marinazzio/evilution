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
              "Use suggest_tests: true to get concrete RSpec test code for surviving mutants."
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
        description: "When true, suggestions for survived mutants include concrete RSpec test code " \
                     "instead of static description text (default: false)"
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
    # rubocop:disable Metrics/ParameterLists
    def call(server_context:, files: [], target: nil, timeout: nil, jobs: nil,
             fail_fast: nil, spec: nil, suggest_tests: nil, verbosity: nil)
      parsed_files, line_ranges = parse_files(Array(files))
      config_opts = build_config_opts(parsed_files, line_ranges, target, timeout, jobs, fail_fast, spec,
                                      suggest_tests)
      config = Evilution::Config.new(**config_opts)
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
    # rubocop:enable Metrics/ParameterLists

    VALID_VERBOSITIES = %w[full summary minimal].freeze

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

    def build_config_opts(files, line_ranges, target, timeout, jobs, fail_fast, spec, suggest_tests)
      opts = { target_files: files, line_ranges: line_ranges, format: :json, quiet: true, skip_config_file: true }
      opts[:target] = target if target
      opts[:timeout] = timeout if timeout
      opts[:jobs] = jobs if jobs
      opts[:fail_fast] = fail_fast if fail_fast
      opts[:spec_files] = spec if spec
      opts[:suggest_tests] = true if suggest_tests
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
