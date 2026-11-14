# frozen_string_literal: true

require_relative "../ast"
require_relative "ancestor_lookup"
require_relative "pattern/filter"
require_relative "skip_sites/presets"

# Decides whether a mutation is skipped during generation, and counts why:
# an `ignore_patterns` pattern matches its node or an ancestor (see
# Pattern::Filter), or its node lies in a site of a `skip_sites` preset
# (see SkipSites::Presets). The two share one parent index per file.
#
# A skipped mutation is counted once per file and mutated source, under the
# first reason it was skipped for: patterns before presets, presets in
# their attribution order.
class Evilution::AST::SkipFilter
  PATTERNS = :ignore_patterns
  private_constant :PATTERNS

  # nil when the config skips nothing.
  def self.for(config)
    patterns = config.ignore_patterns
    sites = config.skip_sites
    return nil if patterns.empty? && sites.empty?

    new(patterns: patterns, sites: sites)
  end

  # patterns: ignore_patterns strings; sites: preset names (Symbols).
  def initialize(patterns:, sites:)
    @ancestor_lookup = Evilution::AST::AncestorLookup.new
    @patterns = Evilution::AST::Pattern::Filter.new(patterns, ancestor_lookup: @ancestor_lookup)
    @presets = Evilution::AST::SkipSites::Presets.build(sites)
    reset_count!
  end

  # file_path, source: the file the node was parsed from and its source;
  # without a source only the node itself is tested. mutated_source: the
  # file as the mutation leaves it, the identity a skip is counted by;
  # without one each skip counts.
  def skip?(node, file_path: nil, source: nil, mutated_source: nil)
    reason = reason_for(node, file_path, source)
    return false unless reason

    @skipped[mutated_source ? [file_path, mutated_source.hash] : Object.new] ||= reason
    true
  end

  # made: the mutations the run makes. One of them can be a skipped mutation
  # made all the same from a node nothing skips, which is not counted.
  def skipped_count(made: [])
    counted(made).length
  end

  # The skips per preset, e.g. { logging: 3 }; presets that skipped nothing
  # are left out.
  def skipped_by_site(made: [])
    counted(made).reject { |reason| reason == PATTERNS }.tally
  end

  def reset_count!
    @skipped = {}
  end

  private

  def reason_for(node, file_path, source)
    return PATTERNS if @patterns.skip?(node, file_path: file_path, source: source)
    return nil if @presets.empty?

    chain = [node, *@ancestor_lookup.ancestors(node, file_path, source)]
    preset = @presets.find { |candidate| candidate.covers?(chain) }
    preset && preset.name
  end

  def counted(made)
    made_keys = made.to_set { |mutation| [mutation.file_path, mutation.mutated_source.hash] }
    @skipped.filter_map { |key, reason| reason unless made_keys.include?(key) }
  end
end
