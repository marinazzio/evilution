# frozen_string_literal: true

require_relative "../operator"

# Resolve a dynamic dispatch with a literal symbol into a direct call:
# `target.send(:reset)` becomes `target.reset`, and the same for `__send__`
# and `public_send`. Remaining arguments, a block-pass and a literal block
# stay attached.
#
# The two forms differ only in visibility checks, so the mutant is emitted
# only where those checks can disagree:
#
# - send / __send__ on an explicit receiver other than self: the direct call
#   raises NoMethodError for a private method. With an implicit or self
#   receiver a private method resolves either way (Ruby 2.7+).
# - public_send with an implicit or self receiver: the direct call reaches a
#   private method that public_send refuses. On any other receiver both
#   refuse it, and only a protected method called from inside its class
#   would differ.
#
# method_missing is reached the same way by both forms.
class Evilution::Mutator::Operator::DynamicDispatchResolution < Evilution::Mutator::Base
  SEND_SELECTORS = %i[send __send__].freeze
  private_constant :SEND_SELECTORS

  OPERATOR_NAMES = %w[
    + - * / % ** == != < > <= >= <=> === =~ !~ ! [] []= << >> & | ^ ~ +@ -@
  ].to_set.freeze
  private_constant :OPERATOR_NAMES

  METHOD_NAME = /\A[[:alpha:]_][[:alnum:]_]*[?!=]?\z/
  private_constant :METHOD_NAME

  def visit_call_node(node)
    selector = literal_selector(node)
    resolve(node, selector) if selector && visibility_can_differ?(node)
    super
  end

  private

  def literal_selector(node)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [Prism::SymbolNode => symbol, *]]

    name = symbol.unescaped
    name if name.match?(METHOD_NAME) || OPERATOR_NAMES.include?(name)
  end

  def visibility_can_differ?(node)
    self_receiver = node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)

    if SEND_SELECTORS.include?(node.name)
      !self_receiver
    else
      node.name == :public_send && self_receiver
    end
  end

  def resolve(node, selector)
    start = node.message_loc.start_offset
    following = following_item(node)

    if following
      replacement = "#{selector}#{node.opening_loc ? "(" : " "}"
      finish = following.start_offset
    else
      replacement = selector
      finish = node.closing_loc ? node.closing_loc.end_offset : node.arguments.end_offset
    end

    add_mutation(offset: start, length: finish - start, replacement: replacement, node: node)
  end

  # The argument after the selector, or the block-pass when the selector is
  # the only argument.
  def following_item(node)
    node.arguments.arguments[1] || (node.block if node.block.is_a?(Prism::BlockArgumentNode))
  end
end
