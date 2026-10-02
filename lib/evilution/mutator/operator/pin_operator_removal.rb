# frozen_string_literal: true

require_relative "../operator"

# Drop the pin of a pattern variable: `in ^expected` becomes `in expected`.
#
# A pinned variable compares the matched value against an existing binding;
# without the pin the same name captures whatever is there, so the pattern
# matches every value. A survivor means no example feeds the pattern a value
# that differs from the pinned one.
class Evilution::Mutator::Operator::PinOperatorRemoval < Evilution::Mutator::Base
  def visit_pinned_variable_node(node)
    remove_pin(node)
    super
  end

  private

  # Not every pin has an unpinned form. Only a local name can stand as a
  # capturing pattern, so `^@expected` and `^$expected` have none; neither does
  # a numbered parameter (`^_1`), nor any pin inside an alternative pattern
  # (`^a | ^b`), which may not capture. Those rewrites do not parse and carry
  # no signal, so they are dropped rather than reported as unparseable.
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
