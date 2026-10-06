# frozen_string_literal: true

require_relative "../guarded_index_fetch"

# A guard that leaves when the key is missing protects what comes after it in
# the same statement list:
#
#   return unless config[:k]
#   style << config[:k]          # fetch cannot raise here
#
# The guard is an `unless` whose condition says the key is there, an `if`
# whose condition says it is not, or `cond or return` -- with a body ending in
# `return`, `next`, `break`, `raise` or `fail`, and no else branch to fall
# through. `next` and `break` leave only the current iteration, which is all
# the statements after them in the block's body belong to.
#
# Nothing between the guard and the read, nor the statement holding the read,
# may change the receiver; that statement is checked whole, since a loop in it
# runs its end before its start the second time round.
class Evilution::Equivalent::Heuristic::GuardedIndexFetch::EarlyExit
  EXIT_NODES = [Prism::ReturnNode, Prism::NextNode, Prism::BreakNode].freeze
  EXIT_CALLS = %i[raise fail].freeze

  def initialize(statements, read)
    @statements = statements
    @read = read
    @condition = Evilution::Equivalent::Heuristic::GuardedIndexFetch::Condition.new(read)
  end

  # child: the statement of this list that holds the read.
  def protects?(child)
    return false unless @statements.is_a?(Prism::StatementsNode)

    list = @statements.body
    position = list.index { |statement| statement.equal?(child) }
    guard = position && nearest_guard(list, position)
    return false unless guard

    list[(guard + 1)..position].none? { |statement| disturbance.in?(statement) }
  end

  private

  # The last guard before the read: an earlier one would have more statements
  # after it to answer for, not fewer.
  def nearest_guard(list, position)
    (0...position).reverse_each.find { |index| guard?(list[index]) }
  end

  def guard?(statement)
    case statement
    when Prism::UnlessNode then leaves?(statement, statement.else_clause) && @condition.proves?(statement.predicate)
    when Prism::IfNode then leaves?(statement, statement.subsequent) && @condition.refutes?(statement.predicate)
    when Prism::OrNode then exit?(statement.right) && @condition.proves?(statement.left)
    else false
    end
  end

  def leaves?(conditional, other_branch)
    body = conditional.statements
    other_branch.nil? && body.is_a?(Prism::StatementsNode) && exit?(body.body.last)
  end

  def exit?(node)
    return true if EXIT_NODES.any? { |type| node.is_a?(type) }

    node.is_a?(Prism::CallNode) && node.receiver.nil? && EXIT_CALLS.include?(node.name)
  end

  def disturbance
    @disturbance ||= Evilution::Equivalent::Heuristic::GuardedIndexFetch::Disturbance.new(@read)
  end
end
