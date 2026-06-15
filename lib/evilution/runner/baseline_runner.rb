# frozen_string_literal: true

require_relative "../runner"
require_relative "../baseline"
require_relative "../spec_resolver"
require_relative "../integration/rspec"
require_relative "../integration/minitest"
require_relative "../coverage_example_filter"
require_relative "../coverage/map_store"
require_relative "../coverage/map_builder"
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

    lexical = build_lexical_filter
    return lexical unless config.coverage_targeting?

    build_coverage_filter(lexical)
  end

  def build_lexical_filter
    Evilution::ExampleFilter.new(
      cache: Evilution::SpecAstCache.new(**config.example_targeting_cache),
      fallback: config.example_targeting_fallback,
      source_cache: Evilution::SourceAstCache.new
    )
  end

  # The coverage map is built (or loaded from cache) once here, in the parent,
  # before any mutation fork. Any failure -- unsupported Ruby, suite error,
  # corrupt cache that cannot rebuild -- degrades to lexical targeting rather
  # than aborting the run (design: never abort, never silently mis-skip).
  def build_coverage_filter(lexical)
    map = resolve_coverage_map
    return lexical unless map

    Evilution::CoverageExampleFilter.new(map: map, lexical: lexical)
  rescue StandardError => e
    warn "evilution: coverage targeting unavailable (#{e.class}: #{e.message}); using lexical targeting"
    lexical
  end

  def resolve_coverage_map
    targets = config.target_files.map { |file| File.expand_path(file, Evilution::PROJECT_ROOT) }
    return nil if targets.empty?

    specs = resolved_spec_files
    return nil if specs.empty? # nothing resolves -> no coverage to capture, lexical handles it

    store = Evilution::Coverage::MapStore.new
    cache_inputs = targets + specs
    return store.load(targets) if store.stale_files(cache_inputs).empty?

    map = Evilution::Coverage::MapBuilder.new(spec_files: specs, target_files: targets).call
    store.save(map, cache_inputs)
    map
  end

  # The RESOLVED spec files for the target sources -- the same lib-mirrored specs
  # full-file targeting already runs cleanly -- NOT the whole suite. EV-7uui:
  # capturing and replaying coverage only within these guarantees the covering
  # examples load in the per-mutation run (cross-file integration specs, which a
  # whole-suite map would surface, fail to bootstrap in isolation and lose kills).
  def resolved_spec_files
    config.target_files
          .flat_map { |file| Array(config.spec_selector.call(file)) }
          .map { |spec| File.expand_path(spec, Evilution::PROJECT_ROOT) }
          .uniq
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
