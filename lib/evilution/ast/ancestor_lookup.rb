# frozen_string_literal: true

require_relative "../ast"
require_relative "parent_index"
require_relative "parse_cache"

# The ancestors of a node within the file it was parsed from, found in the
# file's tree from the shared parse cache.
#
# Only the last source's index is kept: the mutations of a file are made one
# after the other, and an index per file would hold every file's tree for
# the whole run. The operators each read the file anew, so an equal source
# is taken over, and the next check against it compares no bytes.
class Evilution::AST::AncestorLookup
  NONE = [].freeze
  private_constant :NONE

  # Nearest first, up to the top of the source; none without a source.
  def ancestors(node, file_path, source)
    return NONE if source.nil?

    parent_index(file_path, source).enum_for(:each_ancestor, node)
  end

  private

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
