# frozen_string_literal: true

require_relative "../operator"

# Swallow the error of a statement that raises by convention:
# `record.save!` becomes `record.save! rescue nil`.
#
# The mutant behaves like the original until the statement fails; then it
# carries on with nil instead of raising. A survivor means no example makes
# that statement fail and checks the error comes out. It is the inverse of
# RescueRemoval: handling is added where there is none.
#
# Only calls whose failure is part of their contract are reached: bang
# methods, `fetch`, and the conversion functions `Integer`, `Float` and
# `Rational`. Wrapping every statement would mostly report that no test makes
# a log line raise. Statements already covered by a rescue are left alone, as
# is `raise`, whose swallowed form behaves as deleting the statement.
class Evilution::Mutator::Operator::ExceptionSwallow < Evilution::Mutator::Base
  CONVERSION_FUNCTIONS = %i[Integer Float Rational].freeze

  # A bang method name, as opposed to the `!` and `!=` operators.
  BANG_METHOD = /\w!\z/

  # Bangs that do not raise: Ruby's in-place methods mark a change to the
  # receiver, and exit! ends the process without raising.
  NON_RAISING_BANGS = %i[
    uniq! sort! sort_by! select! filter! reject! map! collect! compact! flatten!
    shuffle! reverse! rotate! slice! merge! transform_keys! transform_values!
    gsub! sub! strip! lstrip! rstrip! chomp! chop! squeeze! tr! tr_s! delete!
    downcase! upcase! capitalize! swapcase! unicode_normalize! scrub! encode!
    exit!
  ].freeze

  # Assignments whose value is the statement's call.
  WRITE_TYPES = [
    Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode,
    Prism::ClassVariableWriteNode, Prism::GlobalVariableWriteNode
  ].freeze

  def visit_statements_node(node)
    node.body.each { |statement| swallow(statement) }
    super
  end

  # Everything under a `begin` (or a `def` or block body) with a rescue clause
  # is already handled there, so the visitor does not descend into it.
  def visit_begin_node(node)
    super if node.rescue_clause.nil?
  end

  private

  def swallow(statement)
    call = statement_call(statement)
    return unless call && raising?(call)

    add_mutation(
      offset: statement.location.end_offset,
      length: 0,
      replacement: " rescue nil",
      node: call
    )
  end

  def statement_call(statement)
    statement = statement.value if WRITE_TYPES.include?(statement.class)
    statement if statement.is_a?(Prism::CallNode)
  end

  def raising?(call)
    name = call.name
    return !NON_RAISING_BANGS.include?(name) if name.to_s.match?(BANG_METHOD)
    return raising_fetch?(call) if name == :fetch

    call.receiver.nil? && CONVERSION_FUNCTIONS.include?(name)
  end

  # With a default value or a block, fetch returns that instead of raising.
  def raising_fetch?(call)
    return false if call.receiver.nil? || call.block

    call.arguments.nil? || call.arguments.arguments.length == 1
  end
end
