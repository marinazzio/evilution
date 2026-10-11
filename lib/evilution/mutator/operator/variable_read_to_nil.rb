# frozen_string_literal: true

require_relative "../operator"

# Replace a variable read with `nil`: a local, an instance, class or global
# variable, or `self`.
#
# A survivor means the value read never reaches an assertion — the tests
# would pass whatever the variable held. Where the read is passed as a
# positional argument or interpolated into a string, the mutant is the one
# argument_nil_substitution or string_interpolation already emits, and the
# two are counted once.
#
# Positions where `nil` says nothing new are skipped:
#
# - the receiver of a call, which turns into `nil.name` — a NoMethodError
#   any test that reaches it kills — and likewise the receiver of a write
#   (`counter.total += 1`, `cache[key] ||= value`);
# - a void statement (every statement of a body except the last), which
#   statement_deletion deletes;
# - the condition of an `if`, `unless`, `while` or `until`, where `nil` is
#   the `false` conditional_negation already tries;
# - the left operand of `&&` or `||`, where `nil && b` is the whole
#   expression turned to nil and `nil || b` is `b` promoted;
# - a block-pass argument, `&nil` being the call without its block;
# - a double-splatted read, `**nil` raising before Ruby 3.4;
# - the value a shorthand hash (`name:`) leaves unwritten.
class Evilution::Mutator::Operator::VariableReadToNil < Evilution::Mutator::Base
  include Evilution::Mutator::ReceiverPositions

  def call(subject, **)
    @skipped_nodes = Set.new
    super
  end

  def visit_statements_node(node)
    @skipped_nodes.merge(node.body[...-1])
    super
  end

  def visit_if_node(node)
    @skipped_nodes.add(node.predicate)
    super
  end

  def visit_unless_node(node)
    @skipped_nodes.add(node.predicate)
    super
  end

  def visit_while_node(node)
    @skipped_nodes.add(node.predicate)
    super
  end

  def visit_until_node(node)
    @skipped_nodes.add(node.predicate)
    super
  end

  def visit_and_node(node)
    @skipped_nodes.add(node.left)
    super
  end

  def visit_or_node(node)
    @skipped_nodes.add(node.left)
    super
  end

  def visit_block_argument_node(node)
    @skipped_nodes.add(node.expression)
    super
  end

  def visit_assoc_splat_node(node)
    @skipped_nodes.add(node.value)
    super
  end

  # The read inside has no source of its own: it shares the key's.
  def visit_implicit_node(_node); end

  def visit_local_variable_read_node(node)
    nilify(node)
  end

  def visit_instance_variable_read_node(node)
    nilify(node)
  end

  def visit_class_variable_read_node(node)
    nilify(node)
  end

  def visit_global_variable_read_node(node)
    nilify(node)
  end

  def visit_self_node(node)
    nilify(node)
  end

  private

  def receiver_found(node)
    @skipped_nodes.add(node)
  end

  def nilify(node)
    mutate_to_nil(node) unless @skipped_nodes.include?(node)
  end
end
