# frozen_string_literal: true

require_relative "../operator"

# Removes a trailing literal expression (true/false/nil/integer/symbol) from
# a method body. Targets the idiomatic Ruby pattern `def foo?; side_effect;
# true; end` where the explicit literal return value is the high-signal
# behavior under test — dropping it makes the method return whatever the
# preceding statement evaluates to. Strong against predicates and
# command-query split methods.
class Evilution::Mutator::Operator::LastExpressionRemoval < Evilution::Mutator::Base
  LITERAL_NODE_TYPES = [
    Prism::TrueNode,
    Prism::FalseNode,
    Prism::NilNode,
    Prism::IntegerNode,
    Prism::SymbolNode
  ].freeze

  def visit_def_node(node)
    last_literal = trailing_literal(node)
    if last_literal
      add_mutation(
        offset: last_literal.location.start_offset,
        length: last_literal.location.length,
        replacement: "",
        node: last_literal
      )
    end

    super
  end

  private

  def trailing_literal(node)
    body = node.body
    return nil unless body.is_a?(Prism::StatementsNode)
    return nil if body.body.empty?

    last = body.body.last
    return nil unless LITERAL_NODE_TYPES.any? { |t| last.is_a?(t) }

    last
  end
end
