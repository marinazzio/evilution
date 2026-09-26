# frozen_string_literal: true

require_relative "../operator"

# Replace a conversion with an empty value of its target type: `value.to_a`
# becomes `[]`, `value.to_h` becomes `{}`, `value.to_s` becomes `""`, and the
# same for the implicit `to_ary` / `to_hash` / `to_str` forms.
#
# The type stays right, so a survivor means tests check what kind of value
# comes out but never what it contains.
#
# An empty hash that is the first argument of an unparenthesized call,
# `yield` or `super` is written `({})`: bare `{}` there would be parsed as a
# block. A nil receiver is skipped — its conversion is already empty.
class Evilution::Mutator::Operator::CoercionEmptying < Evilution::Mutator::Base
  EMPTY_VALUES = {
    to_a: "[]", to_ary: "[]",
    to_h: "{}", to_hash: "{}",
    to_s: '""', to_str: '""'
  }.freeze
  private_constant :EMPTY_VALUES

  def call(subject, **)
    @bare_first_arguments = Set.new
    super
  end

  def visit_call_node(node)
    note_bare_first_argument(node, node.opening_loc)
    empty(node) if emptiable?(node)
    super
  end

  def visit_yield_node(node)
    note_bare_first_argument(node, node.lparen_loc)
    super
  end

  def visit_super_node(node)
    note_bare_first_argument(node, node.lparen_loc)
    super
  end

  private

  def note_bare_first_argument(node, opening)
    @bare_first_arguments.add(node.arguments.arguments.first) if opening.nil? && node.arguments
  end

  def emptiable?(node)
    EMPTY_VALUES.key?(node.name) && node.receiver && !node.receiver.is_a?(Prism::NilNode) &&
      node.arguments.nil? && node.block.nil?
  end

  def empty(node)
    value = EMPTY_VALUES.fetch(node.name)
    value = "(#{value})" if value == "{}" && @bare_first_arguments.include?(node)
    replace_span(node: node, target: node, replacement: value)
  end
end
