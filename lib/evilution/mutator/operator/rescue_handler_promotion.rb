# frozen_string_literal: true

require_relative "../operator"
require_relative "../rescue_handlers"

# Run a rescue handler instead of the code it protects:
# `begin; fetch(id); rescue NotFound; default; end` becomes
# `begin; default; end`, a method-level rescue does the same to the method
# body, and `fetch(id) rescue default` becomes `default`.
#
# The happy path never runs, so a survivor means the tests accept the
# fallback value where the real result was expected — they never check what
# the protected code returns.
#
# With several rescue clauses each handler is promoted in its own mutant. An
# else clause goes with the body, since it only runs when nothing is rescued;
# an ensure clause stays. An empty handler becomes `nil`, what a swallowed
# error returns.
#
# Handlers that only make sense inside the rescue are skipped, since promoted
# they fail for that reason alone; Mutator::RescueHandlers holds the rule.
class Evilution::Mutator::Operator::RescueHandlerPromotion < Evilution::Mutator::Base
  def visit_begin_node(node)
    promote_handlers(node) if node.rescue_clause && node.statements
    super
  end

  def visit_rescue_modifier_node(node)
    fallback = node.rescue_expression
    replace(node, fallback.slice, node) if Evilution::Mutator::RescueHandlers.movable?(fallback, nil)
    super
  end

  private

  def promote_handlers(node)
    start_offset = node.statements.location.start_offset
    end_offset = protected_end(node)

    Evilution::Mutator::RescueHandlers.new(node).clauses.each do |clause|
      next unless Evilution::Mutator::RescueHandlers.movable?(clause.statements, clause.reference)

      handler = clause.statements ? clause.statements.slice : "nil"
      add_mutation(offset: start_offset, length: end_offset - start_offset, replacement: handler, node: clause)
    end
  end

  # The body, every rescue clause and an else clause are replaced; an ensure
  # clause and the closing `end` stay. A rescue clause's location runs on
  # through the clauses after it, and an else clause's up to the keyword that
  # follows it, so the span ends at the last clause's own content.
  def protected_end(node)
    else_clause = node.else_clause
    return Evilution::Mutator::RescueHandlers.new(node).clauses.last.location.end_offset if else_clause.nil?

    return else_clause.statements.location.end_offset if else_clause.statements

    else_clause.else_keyword_loc.end_offset
  end

  def replace(target, replacement, node)
    location = target.location
    add_mutation(offset: location.start_offset, length: location.length, replacement: replacement, node: node)
  end
end
