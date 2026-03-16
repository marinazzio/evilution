# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../config"
require_relative "../runner"
require_relative "../reporter/json"

module Evilution
  module MCP
    class MutateTool < ::MCP::Tool
      tool_name "evilution-mutate"
      description "Run mutation testing on Ruby source files"
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
          }
        }
      )

      class << self
        def call(server_context:, files: [], target: nil, timeout: nil, jobs: nil, fail_fast: nil, spec: nil) # rubocop:disable Lint/UnusedMethodArgument
          parsed_files, line_ranges = parse_files(Array(files))
          config_opts = build_config_opts(parsed_files, line_ranges, target, timeout, jobs, fail_fast, spec)
          config = Config.new(**config_opts)
          runner = Runner.new(config: config)
          summary = runner.call
          report = Reporter::JSON.new.call(summary)

          ::MCP::Tool::Response.new([{ type: "text", text: report }])
        rescue Evilution::Error => e
          error_payload = build_error_payload(e)
          ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(error_payload) }], error: true)
        end

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
        end

        def build_config_opts(files, line_ranges, target, timeout, jobs, fail_fast, spec)
          opts = { target_files: files, line_ranges: line_ranges, format: :json, skip_config_file: true }
          opts[:target] = target if target
          opts[:timeout] = timeout if timeout
          opts[:jobs] = jobs if jobs
          opts[:fail_fast] = fail_fast if fail_fast
          opts[:spec_files] = spec if spec
          opts
        end

        def build_error_payload(error)
          error_type = case error
                       when ConfigError then "config_error"
                       when ParseError then "parse_error"
                       else "runtime_error"
                       end

          payload = { type: error_type, message: error.message }
          payload[:file] = error.file if error.file
          { error: payload }
        end
      end
    end
  end
end
