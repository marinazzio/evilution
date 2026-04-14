# frozen_string_literal: true

require_relative "../disable_comment"
require_relative "../ast/sorbet_sig_detector"
require_relative "../ast/pattern/filter"
require_relative "../equivalent/detector"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass

class Evilution::Runner::MutationPlanner
  Plan = Struct.new(:enabled, :equivalent, :skipped_count, :disabled_mutations, keyword_init: true)

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
    mutations, generation_skipped = generate(subjects)
    mutations, disabled = filter_disabled(mutations)
    disabled.each(&:strip_sources!) if config.show_disabled?
    disabled_mutations = config.show_disabled? ? disabled : []

    mutations, sig_skipped = filter_sig_blocks(mutations)
    equivalent, enabled = filter_equivalent(mutations)

    Plan.new(
      enabled: enabled,
      equivalent: equivalent,
      skipped_count: generation_skipped + disabled.length + sig_skipped,
      disabled_mutations: disabled_mutations
    )
  end

  private

  attr_reader :config, :registry

  def generate(subjects)
    filter = build_ignore_filter
    operator_options = build_operator_options
    mutations = subjects.flat_map do |subject|
      registry.mutations_for(subject, filter: filter, operator_options: operator_options)
    end
    skipped = filter ? filter.skipped_count : 0
    [mutations, skipped]
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

    [enabled, disabled]
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

    [enabled, skipped]
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
    Evilution::Equivalent::Detector.new.call(mutations)
  end
end
