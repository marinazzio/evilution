# frozen_string_literal: true

require_relative "../runner"
require_relative "../disable_comment"
require_relative "../ast/sorbet_sig_detector"
require_relative "../ast/pattern/filter"
require_relative "../equivalent/detector"

class Evilution::Runner::MutationPlanner
  Plan = Struct.new(:enabled, :equivalent, :skipped_count, :disabled_mutations, keyword_init: true)

  GenerationResult = Data.define(:mutations, :skipped)
  DisabledFilterResult = Data.define(:enabled, :disabled)
  SigFilterResult = Data.define(:enabled, :skipped)
  EquivalentFilterResult = Data.define(:equivalent, :enabled)
  private_constant :GenerationResult, :DisabledFilterResult, :SigFilterResult, :EquivalentFilterResult

  def initialize(config, registry:, disable_detector: Evilution::DisableComment.new,
                 sig_detector: Evilution::AST::SorbetSigDetector.new)
    @config = config
    @registry = registry
    @disable_detector = disable_detector
    @sig_detector = sig_detector
    @disabled_ranges_cache = {}
    @sig_ranges_cache = {}
  end

  def call(subjects)
    generation = generate(subjects)
    disabled_filter = filter_disabled(generation.mutations)
    disabled_mutations = compute_disabled_mutations(disabled_filter)
    sig_filter = filter_sig_blocks(disabled_filter.enabled)
    equivalent_filter = filter_equivalent(sig_filter.enabled)

    build_plan(equivalent_filter, disabled_mutations, total_skipped(generation, disabled_filter, sig_filter))
  end

  private

  attr_reader :config, :registry

  def compute_disabled_mutations(disabled_filter)
    return [] unless config.show_disabled?

    disabled_filter.disabled.each(&:strip_sources!)
    disabled_filter.disabled
  end

  def total_skipped(generation, disabled_filter, sig_filter)
    generation.skipped + disabled_filter.disabled.length + sig_filter.skipped
  end

  def build_plan(equivalent_filter, disabled_mutations, skipped_count)
    Plan.new(
      enabled: equivalent_filter.enabled,
      equivalent: equivalent_filter.equivalent,
      skipped_count: skipped_count,
      disabled_mutations: disabled_mutations
    )
  end

  def generate(subjects)
    filter = build_ignore_filter
    operator_options = build_operator_options
    mutations = subjects.flat_map do |subject|
      registry.mutations_for(subject, filter: filter, operator_options: operator_options)
    end
    skipped = filter ? filter.skipped_count : 0
    GenerationResult.new(mutations: mutations, skipped: skipped)
  end

  def build_operator_options
    { skip_heredoc_literals: config.skip_heredoc_literals? }
  end

  def build_ignore_filter
    patterns = config.ignore_patterns
    return nil if patterns.nil? || patterns.empty?

    Evilution::AST::Pattern::Filter.new(patterns)
  end

  def filter_disabled(mutations)
    enabled = []
    disabled = []

    mutations.each do |mutation|
      if mutation_disabled?(mutation)
        disabled << mutation
      else
        enabled << mutation
      end
    end

    DisabledFilterResult.new(enabled: enabled, disabled: disabled)
  end

  def mutation_disabled?(mutation)
    ranges = disabled_ranges_for(mutation.file_path)
    ranges.any? { |range| range.cover?(mutation.line) }
  end

  def disabled_ranges_for(file_path)
    @disabled_ranges_cache[file_path] ||= begin
      source = File.read(file_path)
      @disable_detector.call(source)
    rescue SystemCallError
      []
    end
  end

  def filter_sig_blocks(mutations)
    enabled = []
    skipped = 0

    mutations.each do |mutation|
      if mutation_in_sig_block?(mutation)
        skipped += 1
      else
        enabled << mutation
      end
    end

    SigFilterResult.new(enabled: enabled, skipped: skipped)
  end

  def mutation_in_sig_block?(mutation)
    ranges = sig_line_ranges_for(mutation.file_path)
    ranges.any? { |range| range.cover?(mutation.line) }
  end

  def sig_line_ranges_for(file_path)
    @sig_ranges_cache[file_path] ||= begin
      source = File.read(file_path)
      @sig_detector.line_ranges(source)
    rescue SystemCallError
      []
    end
  end

  def filter_equivalent(mutations)
    equivalent, enabled = Evilution::Equivalent::Detector.new.call(mutations)
    EquivalentFilterResult.new(equivalent: equivalent, enabled: enabled)
  end
end
