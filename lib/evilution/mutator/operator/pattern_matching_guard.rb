# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::PatternMatchingGuard < Evilution::Mutator::Base
  def visit_in_node(node)
    pattern = node.pattern
    mutate_guard(pattern, node) if guarded?(pattern)
    super
  end

  private

  def guarded?(pattern)
    pattern.is_a?(Prism::IfNode) || pattern.is_a?(Prism::UnlessNode)
  end

  def mutate_guard(pattern, in_node)
    guard_start = pattern.statements.location.start_offset + pattern.statements.location.length
    guard_end = pattern.predicate.location.start_offset + pattern.predicate.location.length

    remove_guard(guard_start, guard_end, in_node)
    negate_guard(pattern, in_node)
  end

  def remove_guard(guard_start, guard_end, in_node)
    add_mutation(
      offset: guard_start,
      length: guard_end - guard_start,
      replacement: "",
      node: in_node
    )
  end

  def negate_guard(pattern, in_node)
    pred_loc = pattern.predicate.location
    add_mutation(
      offset: pred_loc.start_offset,
      length: pred_loc.length,
      replacement: "!(#{@file_source.byteslice(pred_loc.start_offset, pred_loc.length)})",
      node: in_node
    )
  end
end
