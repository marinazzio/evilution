# frozen_string_literal: true

require "prism"

require_relative "../ast"

# Answers whether a scope body ever reads a given local name — the question an
# operator asks before changing a parameter, since a parameter nothing reads
# makes most such mutations behaviour-preserving.
#
# Scope-aware in the one way that matters here: a block shares the scope it is
# written in, so a read inside one counts, while a nested def opens its own
# scope, where a local of the same name is a different variable. A write is not
# a read.
class Evilution::AST::LocalReads
  def call(node, name)
    return false if node.nil?
    return true if node.is_a?(Prism::LocalVariableReadNode) && node.name.to_s == name

    node.compact_child_nodes.any? do |child|
      next false if child.is_a?(Prism::DefNode)

      call(child, name)
    end
  end
end
