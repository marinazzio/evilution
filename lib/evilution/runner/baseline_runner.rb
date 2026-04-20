# frozen_string_literal: true

require_relative "../baseline"
require_relative "../spec_resolver"
require_relative "../integration/rspec"
require_relative "../integration/minitest"
require_relative "../example_filter"
require_relative "../spec_ast_cache"
require_relative "../source_ast_cache"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass

unless defined?(Evilution::Runner::INTEGRATIONS)
  Evilution::Runner::INTEGRATIONS = {
    rspec: Evilution::Integration::RSpec,
    minitest: Evilution::Integration::Minitest
  }.freeze
end

class Evilution::Runner::BaselineRunner
  def initialize(config, hooks: nil)
    @config = config
    @hooks = hooks
  end

  def integration_class
    @integration_class ||= Evilution::Runner::INTEGRATIONS.fetch(config.integration) do
      raise Evilution::Error, "unknown integration: #{config.integration}"
    end
  end

  def build_integration
    klass = integration_class
    test_files = config.spec_files.empty? ? nil : config.spec_files
    kwargs = {
      test_files: test_files,
      hooks: hooks,
      fallback_to_full_suite: config.fallback_to_full_suite?,
      spec_selector: config.spec_selector
    }
    if klass == Evilution::Integration::RSpec
      kwargs[:related_specs_heuristic] = config.related_specs_heuristic?
      kwargs[:example_filter] = build_example_filter
    end
    klass.new(**kwargs)
  end

  def call(subjects)
    return nil unless config.baseline? && subjects.any?

    log_start
    baseline = Evilution::Baseline.new(timeout: config.timeout, **integration_class.baseline_options)
    result = baseline.call(subjects)
    log_complete(result)
    result
  end

  def neutralization_resolver
    integration_class.baseline_options[:spec_resolver] || Evilution::SpecResolver.new
  end

  def neutralization_fallback_dir
    integration_class.baseline_options[:fallback_dir] || "spec"
  end

  private

  attr_reader :config, :hooks

  def build_example_filter
    return nil unless config.example_targeting?

    Evilution::ExampleFilter.new(
      cache: Evilution::SpecAstCache.new(**config.example_targeting_cache),
      fallback: config.example_targeting_fallback,
      source_cache: Evilution::SourceAstCache.new
    )
  end

  def log_start
    return if config.quiet || !config.text? || !$stderr.tty?

    $stderr.write("Running baseline test suite...\n")
  end

  def log_complete(result)
    return if config.quiet || !config.text? || !$stderr.tty?

    count = result.failed_spec_files.size
    $stderr.write("Baseline complete: #{count} failing spec file#{"s" unless count == 1}\n")
  end
end
