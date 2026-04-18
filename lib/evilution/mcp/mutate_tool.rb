# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../config"
require_relative "../runner"
require_relative "../reporter/json"
require_relative "../spec_resolver"

require_relative "../mcp"

class Evilution::MCP::MutateTool < MCP::Tool
  tool_name "evilution-mutate"
  description "Run mutation testing on Ruby source files and return structured JSON — not parsed CLI text. " \
              "Built for iterative TDD: " \
              "'incremental: true' caches killed/timeout results so rerunning on unchanged files is fast; " \
              "'save_session: true' persists results for later diffing via evilution-session; " \
              "'suggest_tests: true' streams concrete RSpec/Minitest code for each survivor as progress " \
              "events so you can drop fixes straight into a test file. " \
              "Respects .evilution.yml (timeout, jobs, integration, target, ignore_patterns, isolation) by default — " \
              "pair with evilution-info to discover subjects and specs before you call this tool. " \
              "Supports line-range file targeting (lib/foo.rb:15-30), 'target' method filter, explicit 'spec' overrides, " \
              "'fail_fast' for early exit on N survivors, 'baseline: false' to skip the green-suite precheck, " \
              "and 'verbosity' (full/summary/minimal) to match the agent's context budget. " \
              "Survived mutants are enriched beyond `evilution --format json`: each entry includes " \
              "'subject' (Class#method), resolved 'spec_file', and a concrete 'next_step' hint — " \
              "so the agent can jump straight to writing the missing test. " \
              "Prefer this over shelling out to 'evilution' — the response is machine-readable " \
              "and already trimmed for survived-mutant triage."
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
      Evilution::MCP::MutateTool::OptionParser.validate!(opts)
      parsed_files, line_ranges = Evilution::MCP::MutateTool::OptionParser.parse_files(Array(files))
      config = Evilution::MCP::MutateTool::ConfigBuilder.build(
        files: parsed_files,
        line_ranges: line_ranges,
        params: opts
      )
      on_result = Evilution::MCP::MutateTool::ProgressStreamer.build(
        server_context: server_context,
        suggest_tests: opts[:suggest_tests],
        integration: config.integration
      )
      summary = Evilution::Runner.new(config: config, on_result: on_result).call
      report = Evilution::Reporter::JSON.new(
        suggest_tests: opts[:suggest_tests] == true,
        integration: config.integration
      ).call(summary)
      normalized_verbosity = Evilution::MCP::MutateTool::OptionParser.normalize_verbosity(verbosity)
      compact = Evilution::MCP::MutateTool::ReportTrimmer.call(
        report,
        verbosity: normalized_verbosity,
        survived_results: summary.survived_results,
        config: config,
        enricher: Evilution::MCP::MutateTool::SurvivedEnricher
      )

      ::MCP::Tool::Response.new([{ type: "text", text: compact }])
    rescue Evilution::Error => e
      payload = Evilution::MCP::MutateTool::ErrorPayload.build(e)
      ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(payload) }], error: true)
    end
  end
end

require_relative "mutate_tool/error_payload"
require_relative "mutate_tool/option_parser"
require_relative "mutate_tool/config_builder"
require_relative "mutate_tool/report_trimmer"
require_relative "mutate_tool/survived_enricher"
require_relative "mutate_tool/progress_streamer"
