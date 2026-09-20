# frozen_string_literal: true

require "prism"

require_relative "../operator"

# Reassign an optional parameter to its own default at the top of the body:
# `def f(a = 1); body; end` becomes `def f(a = 1); a = 1; body; end`.
#
# Whatever a caller passed is overwritten, so the mutant survives only where
# every example already passes the default — or passes a value the assertions
# never distinguish from it. Where OptionalParameterToRequired asks whether the
# default is ever used, this asks the opposite question: whether any other value
# ever is.
#
# The parameter must be read somewhere in the body, otherwise overwriting it
# changes nothing and the mutant would survive every suite. An endless method is
# left alone: its body is a single expression, and putting a second statement in
# front of it would change what the method returns rather than what it computes.
# KeywordArgument owns optional keyword parameters, and a block's optional
# parameter is left alone for the same reason it is elsewhere — a block ignores
# arity, so the default is not a contract.
class Evilution::Mutator::Operator::OptionalDefaultInjection < Evilution::Mutator::Base
  def visit_def_node(node)
    inject_defaults(node)
    super
  end

  private

  def inject_defaults(node)
    return if node.equal_loc
    return unless node.parameters

    statements = body_statements(node.body)
    return if statements.nil?

    node.parameters.optionals.each { |optional| inject_default(optional, node.body, statements) }
  end

  # The read is looked for across the whole body, rescue and ensure clauses
  # included, since a parameter read only in a rescue clause is still read. The
  # injection itself goes ahead of the leading statements, which is the only
  # place a statement can be added.
  def inject_default(optional, body, statements)
    name = optional.name.to_s
    return if name.start_with?("_")
    return unless Evilution::AST::LocalReads.new.call(body, name)

    first = statements.body.first.location

    add_mutation(
      offset: first.start_offset,
      length: 0,
      replacement: "#{source_of(optional)}; ",
      node: optional
    )
  end

  # A method-level rescue/ensure (`def foo; stmts; rescue; ...; end`) makes the
  # body a BeginNode whose location spans the entire `def...end`. The injection
  # belongs ahead of the leading statements; returns nil for a rescue/ensure-only
  # body and for an empty method, whose body is nil. A body that holds no
  # statements is always nil rather than an empty StatementsNode, so a present
  # node always has a first statement to inject ahead of.
  def body_statements(body)
    return body unless body.is_a?(Prism::BeginNode)

    body.statements
  end
end
