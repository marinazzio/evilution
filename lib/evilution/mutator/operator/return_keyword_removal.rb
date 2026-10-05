# frozen_string_literal: true

require_relative "../operator"
require_relative "../rescue_handlers"

# Drop the `return` keyword and keep its value: `return :neg if x.negative?`
# becomes `:neg if x.negative?`.
#
# Control flow continues past the point where the method used to leave, so a
# survivor means no test notices the code after a guard clause or an early
# return running anyway. ReturnValueRemoval keeps the early exit and drops the
# value; this keeps the value and drops the exit. Several values become an
# array, as `return` would make them: `return a, b` becomes `[a, b]`.
#
# A return in tail position — the method's last statement, the last statement
# of a branch that is itself in tail position, or the tail of a lambda — is
# skipped: its value is the result either way. A return inside a block always
# leaves the method, so it is never tail position. A bare `return` has no
# value to keep.
class Evilution::Mutator::Operator::ReturnKeywordRemoval < Evilution::Mutator::Base
  # For each node that passes a value on, the parts whose value becomes its
  # own. With an else clause a begin body's value is not the result, the
  # else's is; each rescue handler's value can be the result too.
  TAIL_PARTS = {
    Prism::StatementsNode => ->(node) { [node.body.last] },
    Prism::ParenthesesNode => ->(node) { [node.body] },
    Prism::ElseNode => ->(node) { [node.statements] },
    Prism::IfNode => ->(node) { [node.statements, node.subsequent] },
    Prism::UnlessNode => ->(node) { [node.statements, node.else_clause] },
    Prism::CaseNode => ->(node) { [*node.conditions.map(&:statements), node.else_clause] },
    Prism::CaseMatchNode => ->(node) { [*node.conditions.map(&:statements), node.else_clause] },
    Prism::BeginNode => lambda { |node|
      [node.else_clause || node.statements, *Evilution::Mutator::RescueHandlers.new(node).clauses.map(&:statements)]
    }
  }.freeze

  def initialize(**options)
    super
    @tail_returns = Set.new.compare_by_identity
  end

  def visit_def_node(node)
    @tail_returns.merge(tail_returns(node.body))
    super
  end

  def visit_lambda_node(node)
    @tail_returns.merge(tail_returns(node.body))
    super
  end

  def visit_return_node(node)
    drop_keyword(node) if node.arguments && !@tail_returns.include?(node)
    super
  end

  private

  def drop_keyword(node)
    arguments = node.arguments.arguments
    value = if arguments.length == 1 && !arguments.first.is_a?(Prism::SplatNode)
              arguments.first.slice
            else
              "[#{arguments.map(&:slice).join(", ")}]"
            end

    add_mutation(offset: node.location.start_offset, length: node.location.length, replacement: value, node: node)
  end

  # The returns whose value is the value of `node` itself.
  def tail_returns(node)
    return [node] if node.is_a?(Prism::ReturnNode)

    parts = TAIL_PARTS[node.class]
    return [] if parts.nil?

    parts.call(node).compact.flat_map { |part| tail_returns(part) }
  end
end
