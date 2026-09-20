# frozen_string_literal: true

require "prism"

require_relative "../ast"

# Answers whether a scope body ever reads a given local name — the question an
# operator asks before changing a parameter, since a parameter nothing reads
# makes most such mutations behaviour-preserving.
#
# Scope-aware in the ways that matter here. A block shares the scope it is
# written in, so a read inside one counts — unless the block binds the same name
# itself, as a parameter or a block-local, in which case the read is of the
# block's own variable. A nested def opens a scope of its own, where a local of
# the same name is unrelated. A write is not a read.
#
# Shadowing is settled by Prism's own answer rather than by inspecting each
# block's parameter list: a LocalVariableReadNode carries the number of scopes
# between the read and the variable's declaration, so a read refers to the local
# in question exactly when that depth matches the number of block scopes
# descended to reach it.
class Evilution::AST::LocalReads
  def call(node, name, depth = 0)
    return false if node.nil?
    return true if reads?(node, name, depth)

    node.compact_child_nodes.any? do |child|
      next false if child.is_a?(Prism::DefNode)

      call(child, name, depth + (scope?(child) ? 1 : 0))
    end
  end

  private

  def reads?(node, name, depth)
    node.is_a?(Prism::LocalVariableReadNode) && node.name.to_s == name && node.depth == depth
  end

  def scope?(node)
    node.is_a?(Prism::BlockNode) || node.is_a?(Prism::LambdaNode)
  end
end
