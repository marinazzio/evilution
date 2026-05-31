# frozen_string_literal: true

require_relative "../runner"
require_relative "../baseline"
require_relative "../spec_resolver"
require_relative "../integration/rspec"
require_relative "../integration/minitest"
require_relative "../integration/test_unit"
require_relative "../example_filter"
require_relative "../spec_ast_cache"
require_relative "../source_ast_cache"

unless defined?(Evilution::Runner::INTEGRATIONS)
  Evilution::Runner::INTEGRATIONS = {
    rspec: Evilution::Integration::RSpec,
    minitest: Evilution::Integration::Minitest,
    test_unit: Evilution::Integration::TestUnit
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
    kwargs = base_integration_kwargs
    kwargs.merge!(rspec_integration_kwargs) if klass == Evilution::Integration::RSpec
    klass.new(**kwargs)
  end

  def base_integration_kwargs
    {
      test_files: config.spec_files.empty? ? nil : config.spec_files,
      hooks: hooks,
      fallback_to_full_suite: config.fallback_to_full_suite?,
      spec_selector: config.spec_selector
    }
  end

  def rspec_integration_kwargs
    {
      related_specs_heuristic: config.related_specs_heuristic?,
      example_filter: build_example_filter
    }
  end

  def call(subjects)
    return nil unless config.baseline? && subjects.any?

    log_start
    baseline = Evilution::Baseline.new(
      timeout: config.timeout,
      test_files: config.spec_files.empty? ? nil : config.spec_files,
      **integration_class.baseline_options
    )
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
