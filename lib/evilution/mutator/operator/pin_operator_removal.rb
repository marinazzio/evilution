# frozen_string_literal: true

require_relative "../operator"

# Drop the pin of a pattern variable: `in ^expected` becomes `in expected`.
#
# A pinned variable compares the matched value against an existing binding;
# without the pin the same name captures whatever is there, so the pattern
# matches every value. A survivor means no example feeds the pattern a value
# that differs from the pinned one.
class Evilution::Mutator::Operator::PinOperatorRemoval < Evilution::Mutator::Base
  def initialize(**options)
    super
    @alternation_depth = 0
  end

  # An alternative pattern (`^a | ^b`) may not capture, at any depth inside it,
  # so no pin under one has an unpinned form. Tracked here rather than left to
  # the parse check: older Prism releases accept the capture that Ruby rejects.
  def visit_alternation_pattern_node(node)
    @alternation_depth += 1
    super
  ensure
    @alternation_depth -= 1
  end

  def visit_pinned_variable_node(node)
    remove_pin(node) if @alternation_depth.zero?
    super
  end

  private

  # Other pins without an unpinned form are caught by the parse check. Only a
  # local name can stand as a capturing pattern, so `^@expected` and
  # `^$expected` have none, and neither does a numbered parameter (`^_1`).
  # Those rewrites carry no signal, so they are dropped rather than reported
  # as unparseable.
  def remove_pin(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: node.variable.slice,
      node: node,
      skip_unparseable: true
    )
  end
end
