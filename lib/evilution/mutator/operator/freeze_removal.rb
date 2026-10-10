# frozen_string_literal: true

require "prism"

require_relative "../operator"
require_relative "../../ast/class_body"

# Drop the `freeze` of a constant defined in a class or module body:
# `LIST = %w[a b].freeze` becomes `LIST = %w[a b]`.
#
# A survivor means no example tries to change the shared value, so nothing
# shows that it has to stay as it is.
#
# A constant is defined in the class body, outside every method, where no
# subject reaches it. The mutation is attributed to the method anchoring the
# enclosing body (see Evilution::AST::ClassBody); a top-level constant has no
# body to be attributed to. A `freeze` inside a method is left to the generic
# call operators, which already drop it.
class Evilution::Mutator::Operator::FreezeRemoval < Evilution::Mutator::Base
  CONSTANT_WRITES = [Prism::ConstantWriteNode, Prism::ConstantPathWriteNode, Prism::ConstantOrWriteNode].freeze

  # Values that are frozen whether or not `freeze` is called.
  ALWAYS_FROZEN = [
    Prism::SymbolNode, Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode,
    Prism::NilNode, Prism::TrueNode, Prism::FalseNode, Prism::RangeNode, Prism::RegularExpressionNode
  ].freeze

  # The comments a file opens with, where the magic comment has to be.
  LEADING_COMMENTS = /\A(?:[ \t]*(?:#.*)?\n)*/
  FROZEN_STRING_LITERALS = /^[ \t]*#.*frozen[_-]string[_-]literal:[ \t]*true/i
  private_constant :CONSTANT_WRITES, :ALWAYS_FROZEN, :LEADING_COMMENTS, :FROZEN_STRING_LITERALS

  def call(subject, filter: nil)
    @subject = subject
    @file_source = File.read(subject.file_path)
    @mutations = []
    @filter = filter

    constant_writes_for(subject).each { |write| freezes_in(write).each { |freeze_call| remove(freeze_call) } }
    @mutations
  end

  private

  def remove(freeze_call)
    add_mutation(
      offset: freeze_call.location.start_offset,
      length: freeze_call.location.length,
      replacement: freeze_call.receiver.slice,
      node: freeze_call
    )
  end

  def constant_writes_for(subject)
    tree = self.class.parsed_tree_for(subject.file_path, @file_source)

    Evilution::AST::ClassBody.anchored_at(tree, subject.line_number).flat_map do |body|
      body.declarations { |node| CONSTANT_WRITES.include?(node.class) }
    end
  end

  # Every `freeze` call under the node, outermost first.
  def freezes_in(node)
    nested = node.compact_child_nodes.flat_map { |child| freezes_in(child) }
    removable_freeze?(node) ? [node, *nested] : nested
  end

  def removable_freeze?(node)
    return false unless node.is_a?(Prism::CallNode) && node.name == :freeze
    return false if node.receiver.nil? || node.arguments

    !frozen_anyway?(node.receiver)
  end

  # A group has the value of its last expression: `(1..2)`.
  def frozen_anyway?(receiver)
    receiver = receiver.body.body.last while receiver.is_a?(Prism::ParenthesesNode) && receiver.body
    return true if ALWAYS_FROZEN.include?(receiver.class)

    receiver.is_a?(Prism::StringNode) && frozen_string_literals?
  end

  def frozen_string_literals?
    @file_source[LEADING_COMMENTS].match?(FROZEN_STRING_LITERALS)
  end
end
