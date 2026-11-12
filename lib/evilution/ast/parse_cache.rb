# frozen_string_literal: true

require "prism"
require_relative "../ast"

# One parse per file for the whole of mutation planning: the operators that
# look beyond their subject and the ignore filter all want the file's tree.
# A file is parsed again when its source differs from the one cached for it.
module Evilution::AST::ParseCache
  Entry = Data.define(:source_hash, :tree)
  private_constant :Entry

  @trees = {}

  def self.tree_for(file_path, source)
    entry = @trees[file_path]
    return entry.tree if entry && entry.source_hash == source.hash

    tree = Prism.parse(source).value
    @trees[file_path] = Entry.new(source_hash: source.hash, tree: tree)
    tree
  end

  def self.clear!
    @trees = {}
  end
end
