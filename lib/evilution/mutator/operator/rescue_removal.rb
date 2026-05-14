# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::RescueRemoval < Evilution::Mutator::Base
  # Visit BeginNode (not RescueNode directly) so we have access to sibling
  # clauses — `else_clause`, `ensure_clause`, `end_keyword_loc` — which we
  # need to compute the rescue clause's boundary and to drop a soon-to-be-
  # orphaned `else` along with the rescue.
  def visit_begin_node(node)
    walk_rescue_chain(node) { |rescue_node| emit_removal(node, rescue_node) }

    super
  end

  private

  def walk_rescue_chain(begin_node)
    current = begin_node.rescue_clause
    while current
      yield current
      current = current.subsequent
    end
  end

  def emit_removal(begin_node, rescue_node)
    remove_start = line_start_before(rescue_node.keyword_loc.start_offset)
    remove_end = rescue_clause_end(begin_node, rescue_node)
    remove_end = else_end(begin_node) if removing_sole_rescue_orphans_else?(begin_node, rescue_node)

    add_mutation(
      offset: remove_start,
      length: remove_end - remove_start,
      replacement: "",
      node: rescue_node
    )
  end

  # The rescue clause's bytes run from its `rescue` keyword up to the start
  # of the next sibling clause: another `rescue`, then `else`, `ensure`, or
  # the begin's `end`. Using these structural boundaries instead of the
  # statements body fixes the underflow when the body is comment-only or
  # otherwise empty — the old code stopped at the `rescue` keyword and left
  # the exception class name orphaned in the source.
  def rescue_clause_end(begin_node, rescue_node)
    boundary = next_clause_start(begin_node, rescue_node)
    line_start_before(boundary)
  end

  def next_clause_start(begin_node, rescue_node)
    return rescue_node.subsequent.keyword_loc.start_offset if rescue_node.subsequent
    return begin_node.else_clause.else_keyword_loc.start_offset if begin_node.else_clause
    return begin_node.ensure_clause.ensure_keyword_loc.start_offset if begin_node.ensure_clause

    begin_node.end_keyword_loc.start_offset
  end

  # An `else` clause is grammatically tied to a `rescue` chain. Stripping
  # the last remaining rescue without also dropping `else` leaves
  # `begin ... else ... end` which Ruby rejects. Detect: the chain has one
  # rescue, and an else exists.
  def removing_sole_rescue_orphans_else?(begin_node, rescue_node)
    return false unless begin_node.else_clause
    return false unless rescue_node == begin_node.rescue_clause
    return false if rescue_node.subsequent

    true
  end

  def else_end(begin_node)
    if begin_node.ensure_clause
      line_start_before(begin_node.ensure_clause.ensure_keyword_loc.start_offset)
    else
      line_start_before(begin_node.end_keyword_loc.start_offset)
    end
  end

  def line_start_before(offset)
    pos = offset - 1
    pos -= 1 while pos.positive? && @file_source.getbyte(pos) != 0x0A
    pos
  end
end
