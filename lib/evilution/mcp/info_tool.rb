# frozen_string_literal: true

require "json"
require "mcp"
require_relative "../config"
require_relative "../runner"
require_relative "../mutator/registry"
require_relative "../spec_resolver"
require_relative "../ast/pattern/filter"
require_relative "../version"

require_relative "../mcp"

class Evilution::MCP::InfoTool < MCP::Tool
  tool_name "evilution-info"
  description "Discover what evilution sees before running any mutations. " \
              "One tool, three actions: " \
              "'subjects' lists every mutatable method in the target files with its file, line, and mutation count; " \
              "'tests' resolves which spec/test files cover the given sources (so you pick the right --spec before mutating); " \
              "'environment' dumps the effective config (version, ruby, config file, timeout, " \
              "integration, isolation, and every other setting). " \
              "Use this instead of shelling out to 'evilution subjects', 'evilution tests list', or 'evilution environment show' — " \
              "the response is structured JSON so you can plan the next mutation run without parsing CLI text."
  input_schema(
    properties: {
      action: {
        type: "string",
        enum: %w[subjects tests environment],
        description: "Which discovery operation to perform. " \
                     "'subjects' lists mutatable methods; 'tests' resolves specs for sources; 'environment' dumps effective config."
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
        description: "[subjects, tests] When true, ignore .evilution.yml and run with defaults. " \
                     "Default: false — project config is loaded so the result reflects what `evilution` CLI would see."
      }
    },
    required: ["action"]
  )

  VALID_ACTIONS = %w[subjects tests environment].freeze

  class << self
    # rubocop:disable Lint/UnusedMethodArgument
    def call(server_context:, action: nil, files: nil, target: nil, spec: nil, integration: nil, skip_config: nil)
      return error_response("config_error", "action is required") unless action
      return error_response("config_error", "unknown action: #{action}") unless VALID_ACTIONS.include?(action)

      parsed_files, line_ranges = parse_files(Array(files)) if files

      case action
      when "subjects"
        subjects_action(files: parsed_files, line_ranges: line_ranges, target: target,
                        integration: integration, skip_config: skip_config)
      when "tests"
        tests_action(files: parsed_files, spec: spec, integration: integration, skip_config: skip_config)
      when "environment"
        environment_action
      end
    rescue Evilution::Error => e
      error_response_for(e)
    end
    # rubocop:enable Lint/UnusedMethodArgument

    private

    def parse_files(raw_files)
      files = []
      ranges = {}

      raw_files.each do |arg|
        file, range_str = arg.split(":", 2)
        files << file
        ranges[file] = parse_line_range(range_str) if range_str
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

    def subjects_action(files:, line_ranges:, target:, integration:, skip_config:)
      return error_response("config_error", "files is required") if files.nil? || files.empty?

      config = build_subjects_config(files: files, line_ranges: line_ranges,
                                     target: target, integration: integration, skip_config: skip_config)
      runner = Evilution::Runner.new(config: config)
      subjects = runner.parse_and_filter_subjects

      registry = Evilution::Mutator::Registry.default
      filter = build_subject_filter(config)
      operator_options = { skip_heredoc_literals: config.skip_heredoc_literals? }

      entries = subjects.map do |subj|
        count = registry.mutations_for(subj, filter: filter, operator_options: operator_options).length
        { "name" => subj.name, "file" => subj.file_path, "line" => subj.line_number, "mutations" => count }
      ensure
        subj.release_node!
      end

      success_response(
        "subjects" => entries,
        "total_subjects" => entries.length,
        "total_mutations" => entries.sum { |e| e["mutations"] }
      )
    end

    def tests_action(files:, spec:, integration:, skip_config:)
      return error_response("config_error", "files is required") if files.nil? || files.empty?

      config = build_tests_config(files: files, spec: spec, integration: integration, skip_config: skip_config)
      return explicit_specs_response(files, config.spec_files) if config.spec_files.any?

      resolver = resolver_for_integration(config.integration)
      resolved, unresolved = resolve_specs(files, resolver)
      success_response(
        "specs" => resolved,
        "unresolved" => unresolved,
        "total_sources" => files.length,
        "total_specs" => resolved.map { |r| r["spec"] }.uniq.length
      )
    end

    def build_subjects_config(files:, line_ranges:, target:, integration:, skip_config:)
      opts = { target_files: files, line_ranges: line_ranges || {} }
      opts[:skip_config_file] = true if skip_config
      opts[:target] = target if target
      opts[:integration] = integration if integration
      Evilution::Config.new(**opts)
    end

    def build_tests_config(files:, spec:, integration:, skip_config:)
      opts = { target_files: files }
      opts[:skip_config_file] = true if skip_config
      opts[:spec_files] = spec if spec
      opts[:integration] = integration if integration
      Evilution::Config.new(**opts)
    end

    def resolver_for_integration(integration)
      integration_class = Evilution::Runner::INTEGRATIONS[integration.to_sym]
      return Evilution::SpecResolver.new unless integration_class

      integration_class.baseline_options[:spec_resolver] || Evilution::SpecResolver.new
    end

    def explicit_specs_response(files, spec_files)
      success_response(
        "specs" => spec_files.map { |f| { "source" => nil, "spec" => f } },
        "unresolved" => [],
        "total_sources" => files.length,
        "total_specs" => spec_files.length
      )
    end

    def resolve_specs(files, resolver)
      resolved = []
      unresolved = []
      files.each do |source|
        found = resolver.call(source)
        if found
          resolved << { "source" => source, "spec" => found }
        else
          unresolved << source
        end
      end
      [resolved, unresolved]
    end

    def environment_action
      config = Evilution::Config.new(skip_config_file: false)
      config_file = Evilution::Config::CONFIG_FILES.find { |path| File.exist?(path) }

      success_response(
        "version" => Evilution::VERSION,
        "ruby" => RUBY_VERSION,
        "config_file" => config_file,
        "settings" => environment_settings(config)
      )
    end

    def error_response_for(error)
      type = case error
             when Evilution::ConfigError then "config_error"
             when Evilution::ParseError then "parse_error"
             else "runtime_error"
             end
      error_response(type, error.message)
    end

    def environment_settings(config)
      {
        "timeout" => config.timeout,
        "format" => config.format,
        "integration" => config.integration,
        "jobs" => config.jobs,
        "isolation" => config.isolation,
        "baseline" => config.baseline,
        "incremental" => config.incremental,
        "fail_fast" => config.fail_fast,
        "min_score" => config.min_score,
        "suggest_tests" => config.suggest_tests,
        "save_session" => config.save_session,
        "target" => config.target,
        "skip_heredoc_literals" => config.skip_heredoc_literals,
        "ignore_patterns" => config.ignore_patterns
      }
    end

    def build_subject_filter(config)
      return nil if config.ignore_patterns.empty?

      Evilution::AST::Pattern::Filter.new(config.ignore_patterns)
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
