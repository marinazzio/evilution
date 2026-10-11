# frozen_string_literal: true

require_relative "../operator"

# Ask whether the key is there instead of reading it: `config[:size]`
# becomes `config.key?(:size)`.
#
# The value turns into a boolean. A survivor means the tests only notice
# that something came back — a condition taken, a truthy result — and never
# what the lookup returned.
#
# Only a read with one plain argument qualifies, `key?` taking exactly one.
# An integer or range index is skipped: it points at an Array or a String,
# which has no `key?`, so the mutant would only raise NoMethodError. A read
# in void statement position is left to statement_deletion, its value being
# discarded either way. Index writes are another method altogether.
class Evilution::Mutator::Operator::IndexToKeyPredicate < Evilution::Mutator::Base
  # Argument shapes `key?` cannot take as its one key.
  NON_KEY_ARGUMENTS = [
    Prism::SplatNode,
    Prism::KeywordHashNode,
    Prism::BlockArgumentNode,
    Prism::ForwardingArgumentsNode,
    Prism::IntegerNode,
    Prism::RangeNode
  ].freeze
  private_constant :NON_KEY_ARGUMENTS

  def call(subject, **)
    @void_statements = Set.new
    super
  end

  def visit_statements_node(node)
    @void_statements.merge(node.body[...-1])
    super
  end

  def visit_call_node(node)
    key = key_argument(node)
    replace_span(node: node, target: node, replacement: key_predicate(node, key)) if key
    super
  end

  private

  def key_argument(node)
    return unless node.name == :[] && !@void_statements.include?(node)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [argument]]

    argument unless NON_KEY_ARGUMENTS.any? { |type| argument.is_a?(type) }
  end

  def key_predicate(node, key)
    operator = node.safe_navigation? ? "&." : "."
    "#{source_of(node.receiver)}#{operator}key?(#{source_of(key)})"
  end
end
