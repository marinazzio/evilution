# frozen_string_literal: true

require_relative "../pattern"
require_relative "../parent_index"
require_relative "parser"

# Decides whether a mutation is ignored: it is when a pattern matches the
# mutated node or any of its ancestors, up to the top of the source the node
# was parsed from.
class Evilution::AST::Pattern::Filter
  NO_ANCESTORS = [].freeze
  private_constant :NO_ANCESTORS

  attr_reader :skipped_count

  def initialize(patterns)
    @matchers = patterns.map { |p| Evilution::AST::Pattern::Parser.new(p).parse }
    @skipped_count = 0
  end

  # source: the source the node was parsed from, where its ancestors are
  # found; without it only the node is tested. The ancestors are looked up
  # only when the node itself matches no pattern. A skipped mutation is
  # counted once, however many of its nodes match.
  def skip?(node, source: nil)
    return false if @matchers.empty?
    return false unless matches?(node) || ancestors(node, source).any? { |ancestor| matches?(ancestor) }

    @skipped_count += 1
    true
  end

  def reset_count!
    @skipped_count = 0
  end

  private

  def matches?(node)
    @matchers.any? { |m| m.match?(node) }
  end

  def ancestors(node, source)
    return NO_ANCESTORS if source.nil?

    parent_index(source).enum_for(:each_ancestor, node)
  end

  # Only the last source's index is kept: the mutations of a file are made one
  # after the other, and an index per file would hold every file's tree for
  # the whole run. The operators each read the file anew, so an equal source
  # is taken over, and the next check against it compares no bytes.
  def parent_index(source)
    unless source.equal?(@indexed_source)
      @parent_index = Evilution::AST::ParentIndex.new(Prism.parse(source).value) unless source == @indexed_source
      @indexed_source = source
    end
    @parent_index
  end
end
