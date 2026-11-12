# frozen_string_literal: true

require_relative "../pattern"
require_relative "../parent_index"
require_relative "../parse_cache"
require_relative "parser"

# Decides whether a mutation is ignored: it is when a pattern matches the
# mutated node or any of its ancestors, up to the top of the source the node
# was parsed from.
class Evilution::AST::Pattern::Filter
  NO_ANCESTORS = [].freeze
  private_constant :NO_ANCESTORS

  def initialize(patterns)
    @matchers = patterns.map { |p| Evilution::AST::Pattern::Parser.new(p).parse }
    reset_count!
  end

  # file_path, source: the file the node was parsed from and its source, where
  # its ancestors are found; without a source only the node is tested. The
  # ancestors are looked up only when the node itself matches no pattern.
  #
  # mutated_source: the file as the mutation leaves it. Two operators can make
  # the same change, which the run makes once, so an ignored mutation is
  # counted once per file and mutated source, however many of its nodes
  # match. Without one each skip counts.
  def skip?(node, file_path: nil, source: nil, mutated_source: nil)
    return false if @matchers.empty?
    return false unless matches?(node) || ancestors(node, file_path, source).any? { |ancestor| matches?(ancestor) }

    @skipped << (mutated_source ? skip_key(file_path, mutated_source) : Object.new)
    true
  end

  # made: the mutations the run makes. One of them can be an ignored mutation
  # made all the same from a node no pattern matches, which is not counted.
  def skipped_count(made: [])
    made_keys = made.to_set { |mutation| skip_key(mutation.file_path, mutation.mutated_source) }
    @skipped.count { |key| !made_keys.include?(key) }
  end

  def reset_count!
    @skipped = Set.new
  end

  private

  # The hash stands in for the mutated source, which would keep a copy of the
  # file per ignored mutation.
  def skip_key(file_path, mutated_source)
    [file_path, mutated_source.hash]
  end

  def matches?(node)
    @matchers.any? { |m| m.match?(node) }
  end

  def ancestors(node, file_path, source)
    return NO_ANCESTORS if source.nil?

    parent_index(file_path, source).enum_for(:each_ancestor, node)
  end

  # Only the last source's index is kept: the mutations of a file are made one
  # after the other, and an index per file would hold every file's tree for
  # the whole run. The operators each read the file anew, so an equal source
  # is taken over, and the next check against it compares no bytes.
  def parent_index(file_path, source)
    unless source.equal?(@indexed_source)
      unless source == @indexed_source
        @parent_index = Evilution::AST::ParentIndex.new(Evilution::AST::ParseCache.tree_for(file_path, source))
      end
      @indexed_source = source
    end
    @parent_index
  end
end
