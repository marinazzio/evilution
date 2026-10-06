# frozen_string_literal: true

require_relative "../guarded_index_fetch"

# One node that may guard a read: an `if` (ternary and modifier forms
# included), an `unless` with an else, or an `&&`. It protects the part that
# runs only when its condition held -- provided the condition says the key is
# there and that part leaves the receiver alone.
class Evilution::Equivalent::Heuristic::GuardedIndexFetch::Guard
  def initialize(node, read)
    @node = node
    @read = read
  end

  def protects?(child)
    guarded = guarded_part
    return false unless guarded && guarded.equal?(child)

    Evilution::Equivalent::Heuristic::GuardedIndexFetch::Condition.new(@read).proves?(condition) &&
      !Evilution::Equivalent::Heuristic::GuardedIndexFetch::Disturbance.new(@read).in?(guarded)
  end

  private

  def guarded_part
    case @node
    when Prism::IfNode then @node.statements
    when Prism::UnlessNode then @node.else_clause
    when Prism::AndNode then @node.right
    end
  end

  def condition
    @node.is_a?(Prism::AndNode) ? @node.left : @node.predicate
  end
end
