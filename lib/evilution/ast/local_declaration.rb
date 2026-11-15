# frozen_string_literal: true

require "prism"

require_relative "../ast"

# Whether Ruby source assigns a local variable. Ruby decides while parsing
# which names are locals: once an assignment to `factor` has been read, a later
# `factor` reads the local, even when the assignment never ran. A change to
# such an assignment can therefore change what other lines do, though its own
# line never runs.
#
# The source can be lines cut out of a file, which need not parse on their
# own; Prism still builds a tree for what it can. With no source at all the
# answer is yes, the one that asks for a test run.
class Evilution::AST::LocalDeclaration
  DECLARING = [
    Prism::LocalVariableWriteNode, Prism::LocalVariableOperatorWriteNode,
    Prism::LocalVariableOrWriteNode, Prism::LocalVariableAndWriteNode,
    Prism::LocalVariableTargetNode
  ].freeze
  private_constant :DECLARING

  def in?(source)
    return true if source.nil?

    declares?(Prism.parse(source).value)
  end

  private

  def declares?(node)
    return true if DECLARING.any? { |type| node.is_a?(type) }

    node.compact_child_nodes.any? { |child| declares?(child) }
  end
end
