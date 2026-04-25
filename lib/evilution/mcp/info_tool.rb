# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../config"
require_relative "../runner"
require_relative "../mutator/registry"
require_relative "../result/mutation_result"
require_relative "../spec_resolver"
require_relative "../ast/pattern/filter"
require_relative "../version"

require_relative "../mcp"

class Evilution::MCP::InfoTool < MCP::Tool
  VALID_ACTIONS = %w[subjects tests environment statuses].freeze

  tool_name "evilution-info"
  description "Discover what evilution sees before running any mutations. " \
              "One tool, four actions: " \
              "'subjects' lists every mutatable method in the target files with its file, line, and mutation count; " \
              "'tests' resolves which spec/test files cover the given sources (so you pick the right --spec before mutating); " \
              "'environment' dumps the effective config (version, ruby, config file, timeout, " \
              "integration, isolation, and every other setting); " \
              "'statuses' returns the mutation-result status glossary (killed/survived/neutral/error/etc.) with " \
              "per-status meaning and scoring semantics so agents can triage results without guessing. " \
              "Use this instead of shelling out to 'evilution subjects', 'evilution tests list', or 'evilution environment show' — " \
              "the response is structured JSON so you can plan the next mutation run without parsing CLI text."
  input_schema(
    properties: {
      action: {
        type: "string",
        enum: VALID_ACTIONS,
        description: "Which discovery operation to perform. " \
                     "'subjects' lists mutatable methods; 'tests' resolves specs for sources; " \
                     "'environment' dumps effective config; 'statuses' returns the result-status glossary."
      },
      files: {
        type: "array",
        items: { type: "string" },
        description: "[subjects, tests] Target source files. Supports line-range syntax " \
                     "(lib/foo.rb:15-30, lib/foo.rb:15, lib/foo.rb:15-); for 'tests' the range is " \
                     "stripped before spec resolution."
      },
      target: {
        type: "string",
        description: "[subjects] Filter expression: method (Foo#bar), type (Foo#/Foo.), namespace (Foo*), class (Foo)"
      },
      spec: {
        type: "array",
        items: { type: "string" },
        description: "[tests] Explicit spec files to return instead of auto-resolving from sources"
      },
      integration: {
        type: "string",
        description: "[subjects, tests] Test integration (rspec, minitest) — 'tests' selects " \
                     "the matching spec resolver (spec/*_spec.rb for rspec, test/*_test.rb for minitest)"
      },
      skip_config: {
        type: "boolean",
        description: "[subjects, tests] When true, ignore .evilution.yml / config/evilution.yml; " \
                     "explicit tool parameters still apply. " \
                     "Default: false — project config is loaded so the result reflects what `evilution` CLI would see."
      }
    },
    required: ["action"]
  )

  class << self
    # rubocop:disable Lint/UnusedMethodArgument
    def call(server_context:, action: nil, files: nil, target: nil, spec: nil, integration: nil, skip_config: nil)
      return ResponseFormatter.error("config_error", "action is required") unless action
      return ResponseFormatter.error("config_error", "unknown action: #{action}") unless ACTIONS.key?(action)

      parsed_files, line_ranges = RequestParser.parse_files(Array(files)) if files

      ACTIONS[action].call(
        files: parsed_files, line_ranges: line_ranges, target: target, spec: spec,
        integration: integration, skip_config: skip_config
      )
    rescue Evilution::Error => e
      ResponseFormatter.error_for(e)
    end
    # rubocop:enable Lint/UnusedMethodArgument
  end
end

require_relative "info_tool/request_parser"
require_relative "info_tool/error_mapper"
require_relative "info_tool/response_formatter"
require_relative "info_tool/status_glossary"
require_relative "info_tool/config_factory"
require_relative "info_tool/actions"
require_relative "info_tool/actions/base"
require_relative "info_tool/actions/subjects"
require_relative "info_tool/actions/tests"
require_relative "info_tool/actions/environment"
require_relative "info_tool/actions/statuses"

Evilution::MCP::InfoTool.const_set(:ACTIONS, {
  "subjects" => Evilution::MCP::InfoTool::Actions::Subjects,
  "tests" => Evilution::MCP::InfoTool::Actions::Tests,
  "environment" => Evilution::MCP::InfoTool::Actions::Environment,
  "statuses" => Evilution::MCP::InfoTool::Actions::Statuses
}.freeze)
Evilution::MCP::InfoTool.send(:private_constant, :ACTIONS)

unless Evilution::MCP::InfoTool.send(:const_get, :ACTIONS).keys == Evilution::MCP::InfoTool::VALID_ACTIONS
  raise "InfoTool action drift: ACTIONS keys do not match VALID_ACTIONS"
end
