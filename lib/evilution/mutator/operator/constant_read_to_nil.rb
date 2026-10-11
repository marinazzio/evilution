# frozen_string_literal: true

require_relative "../operator"

# Replace a constant reference with `nil`: `MAX` becomes `nil`, and a path
# such as `Config::MAX` goes as a whole.
#
# A survivor means the constant's value never reaches an assertion — the
# tests would pass whatever it held.
#
# Four positions are skipped as noise. A constant used as the receiver of a
# call turns into `nil.new`, a NoMethodError any test that reaches it kills.
# The namespace of a path would leave `nil::MAX`, a TypeError; the path is
# nil-ified instead. A constant in void statement position (every statement
# of a body except the last) has no value to replace; deleting it is
# statement_deletion's job. And the exception classes of a `rescue` clause
# belong to the rescue operators — `rescue nil` only fails once something is
# raised, and then with a TypeError of its own.
class Evilution::Mutator::Operator::ConstantReadToNil < Evilution::Mutator::Base
  def call(subject, **)
    @skipped_nodes = Set.new
    super
  end

  def visit_statements_node(node)
    @skipped_nodes.merge(node.body[...-1])
    super
  end

  def visit_call_node(node)
    @skipped_nodes.add(node.receiver)
    super
  end

  def visit_rescue_node(node)
    @skipped_nodes.merge(node.exceptions)
    super
  end

  def visit_constant_path_node(node)
    @skipped_nodes.add(node.parent)
    nilify(node)
    super
  end

  def visit_constant_read_node(node)
    nilify(node)
    super
  end

  private

  def nilify(node)
    mutate_to_nil(node) unless @skipped_nodes.include?(node)
  end
end
