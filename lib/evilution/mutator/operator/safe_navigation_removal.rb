# frozen_string_literal: true

require_relative "../operator"

# Replace safe navigation with a plain call: `user&.name` becomes
# `user.name`, and the same for the `||=`, `&&=` and operator-write forms.
#
# The mutant only differs when the receiver is nil, where it raises
# NoMethodError instead of short-circuiting. A survivor means no test ever
# reaches the call with a nil receiver, so the `&.` is unexercised.
#
# Receivers that can never be nil — `self` and literals — are skipped, since
# the mutant is equivalent there.
class Evilution::Mutator::Operator::SafeNavigationRemoval < Evilution::Mutator::Base
  NEVER_NIL_RECEIVERS = [
    Prism::SelfNode,
    Prism::StringNode,
    Prism::InterpolatedStringNode,
    Prism::XStringNode,
    Prism::InterpolatedXStringNode,
    Prism::SymbolNode,
    Prism::InterpolatedSymbolNode,
    Prism::IntegerNode,
    Prism::FloatNode,
    Prism::RationalNode,
    Prism::ImaginaryNode,
    Prism::ArrayNode,
    Prism::HashNode,
    Prism::RangeNode,
    Prism::RegularExpressionNode,
    Prism::InterpolatedRegularExpressionNode,
    Prism::TrueNode,
    Prism::FalseNode,
    Prism::LambdaNode
  ].freeze
  private_constant :NEVER_NIL_RECEIVERS

  def visit_call_node(node)
    mutate_safe_navigation(node)
    super
  end

  def visit_call_or_write_node(node)
    mutate_safe_navigation(node)
    super
  end

  def visit_call_and_write_node(node)
    mutate_safe_navigation(node)
    super
  end

  def visit_call_operator_write_node(node)
    mutate_safe_navigation(node)
    super
  end

  private

  def mutate_safe_navigation(node)
    return unless node.safe_navigation?
    return if NEVER_NIL_RECEIVERS.any? { |type| node.receiver.is_a?(type) }

    operator = node.call_operator_loc
    add_mutation(offset: operator.start_offset, length: operator.length, replacement: ".", node: node)
  end
end
