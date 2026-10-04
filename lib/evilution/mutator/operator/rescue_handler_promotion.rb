# frozen_string_literal: true

require_relative "../operator"
require_relative "../../ast/local_reads"

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
# they fail for that reason alone: one that reads the rescued exception (its
# `=> e` variable or `$!`), re-raises it with a bare `raise` / `fail`, or
# retries.
class Evilution::Mutator::Operator::RescueHandlerPromotion < Evilution::Mutator::Base
  EXCEPTION_GLOBALS = %i[$! $@].freeze
  RERAISING_METHODS = %i[raise fail].freeze

  def visit_begin_node(node)
    promote_handlers(node) if node.rescue_clause && node.statements
    super
  end

  def visit_rescue_modifier_node(node)
    fallback = node.rescue_expression
    replace(node, fallback.slice, node) if promotable?(fallback, nil)
    super
  end

  private

  def promote_handlers(node)
    start_offset = node.statements.location.start_offset
    end_offset = protected_end(node)

    rescue_clauses(node).each do |clause|
      next unless promotable?(clause.statements, clause.reference)

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
    return rescue_clauses(node).last.location.end_offset if else_clause.nil?

    return else_clause.statements.location.end_offset if else_clause.statements

    else_clause.else_keyword_loc.end_offset
  end

  def rescue_clauses(node)
    clauses = []
    clause = node.rescue_clause
    while clause
      clauses << clause
      clause = clause.subsequent
    end
    clauses
  end

  def promotable?(handler, reference)
    return true if handler.nil?

    !reads_exception?(handler, reference) && !rescue_only?(handler)
  end

  def reads_exception?(handler, reference)
    return true if nodes_in(handler).any? { |node| exception_global?(node) }
    return false if reference.nil?
    return true unless reference.is_a?(Prism::LocalVariableTargetNode)

    name = reference.name.to_s
    !name.start_with?("_") && Evilution::AST::LocalReads.new.call(handler, name)
  end

  def exception_global?(node)
    node.is_a?(Prism::GlobalVariableReadNode) && EXCEPTION_GLOBALS.include?(node.name)
  end

  # A bare `raise` / `fail` re-raises the rescued error and `retry` only
  # parses inside a rescue.
  def rescue_only?(handler)
    nodes_in(handler).any? do |node|
      node.is_a?(Prism::RetryNode) ||
        (node.is_a?(Prism::CallNode) && node.receiver.nil? && RERAISING_METHODS.include?(node.name) &&
          node.arguments.nil?)
    end
  end

  def nodes_in(node)
    [node, *node.compact_child_nodes.flat_map { |child| nodes_in(child) }]
  end

  def replace(target, replacement, node)
    location = target.location
    add_mutation(offset: location.start_offset, length: location.length, replacement: replacement, node: node)
  end
end
