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
        description: "[subjects, tests] Target source files (supports line-range syntax like lib/foo.rb:15-30)"
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
      spec_dir: {
        type: "string",
        description: "[tests] Include all specs in this directory"
      },
      integration: {
        type: "string",
        description: "[subjects, tests] Test integration (rspec, minitest) — affects spec resolution"
      }
    },
    required: ["action"]
  )

  VALID_ACTIONS = %w[subjects tests environment].freeze

  class << self
    # rubocop:disable Lint/UnusedMethodArgument
    def call(server_context:, action: nil, files: nil, target: nil, spec: nil, spec_dir: nil, integration: nil)
      return error_response("config_error", "action is required") unless action
      return error_response("config_error", "unknown action: #{action}") unless VALID_ACTIONS.include?(action)

      case action
      when "subjects"
        subjects_action(files: files, target: target, integration: integration)
      when "tests"
        tests_action(files: files, spec: spec, spec_dir: spec_dir, integration: integration)
      when "environment"
        environment_action
      end
    end
    # rubocop:enable Lint/UnusedMethodArgument

    private

    def subjects_action(files:, target:, integration:)
      return error_response("config_error", "files is required") if files.nil? || files.empty?

      config_opts = { target_files: files, skip_config_file: true }
      config_opts[:target] = target if target
      config_opts[:integration] = integration if integration
      config = Evilution::Config.new(**config_opts)

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
    rescue Evilution::Error => e
      error_response("config_error", e.message)
    end

    def tests_action(files:, spec:, spec_dir:, integration:)
      return error_response("config_error", "files is required") if files.nil? || files.empty?

      config = build_tests_config(files: files, spec: spec, spec_dir: spec_dir, integration: integration)
      return explicit_specs_response(files, config.spec_files) if config.spec_files.any?

      resolved, unresolved = resolve_specs(files)
      success_response(
        "specs" => resolved,
        "unresolved" => unresolved,
        "total_sources" => files.length,
        "total_specs" => resolved.map { |r| r["spec"] }.uniq.length
      )
    rescue Evilution::Error => e
      error_response("config_error", e.message)
    end

    def build_tests_config(files:, spec:, spec_dir:, integration:)
      opts = { target_files: files, skip_config_file: true }
      opts[:spec_files] = spec if spec
      opts[:spec_dir] = spec_dir if spec_dir
      opts[:integration] = integration if integration
      Evilution::Config.new(**opts)
    end

    def explicit_specs_response(files, spec_files)
      success_response(
        "specs" => spec_files.map { |f| { "source" => nil, "spec" => f } },
        "unresolved" => [],
        "total_sources" => files.length,
        "total_specs" => spec_files.length
      )
    end

    def resolve_specs(files)
      resolver = Evilution::SpecResolver.new
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
    rescue Evilution::Error => e
      error_response("config_error", e.message)
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
