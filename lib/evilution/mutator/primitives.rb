# frozen_string_literal: true

require_relative "../mutator"

# Mutation shapes shared across the operator families: replacing an
# expression with `nil`, and replacing an expression with the source of one
# of its children. Both are built on Base#add_mutation, so the
# equivalent-mutant filter and the heredoc-span guards still apply.
#
# Unlike a bare add_mutation call, these skip rather than emit when the
# result would not parse in its surrounding context. A promotion that does
# not parse is noise rather than signal, so it never reaches the
# `unparseable` bucket the point operators still populate.
module Evilution::Mutator::Primitives
  private

  # Replace `target`'s byte span with `nil`, attributing the mutation to
  # `node`. `target` defaults to `node`; pass an inner node to nil out a body
  # while keeping the reported location on the enclosing construct.
  def mutate_to_nil(node, target: node)
    replace_span(node: node, target: target, replacement: "nil")
  end

  # Replace `target`'s byte span with `child`'s source, verbatim. `child` may
  # be nil — Prism leaves optional slots (a call's receiver, an if's else)
  # empty — in which case there is nothing to promote.
  def promote_child(node, child, target: node)
    return nil if child.nil?

    replace_span(node: node, target: target, replacement: source_of(child))
  end

  def replace_span(node:, target:, replacement:)
    return nil if target.nil?

    location = target.location
    return nil if replacement == byteslice_source(location.start_offset, location.length)

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: replacement,
      node: node,
      skip_unparseable: true
    )
  end

  def source_of(child)
    location = child.location
    byteslice_source(location.start_offset, location.length)
  end

  # `operand`'s source, parenthesized unless it is a primary expression — so
  # it can take a method call: `a + b` becomes `(a + b)` in `(a + b).eql?(c)`.
  def receiver_source(operand)
    primary_operand?(operand) ? source_of(operand) : "(#{source_of(operand)})"
  end

  PRIMARY_OPERANDS = [
    Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode,
    Prism::GlobalVariableReadNode, Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::SelfNode,
    Prism::ParenthesesNode, Prism::StringNode, Prism::IntegerNode, Prism::FloatNode, Prism::ArrayNode
  ].freeze
  private_constant :PRIMARY_OPERANDS

  METHOD_NAME = /\A[[:alpha:]_]/
  private_constant :METHOD_NAME

  # A named method call or an index (`a.size`, `a[0]`) binds tighter than a
  # following `.`; an operator send (`a + b`, `!a`, `-a`) does not.
  def primary_operand?(operand)
    return true if PRIMARY_OPERANDS.any? { |type| operand.is_a?(type) }

    operand.is_a?(Prism::CallNode) && (operand.name.match?(METHOD_NAME) || operand.name == :[])
  end
end
