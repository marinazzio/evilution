# frozen_string_literal: true

require "prism"

require_relative "../operator"

# Give a forwarding `super` an empty argument list: `def f(a); super; end`
# becomes `def f(a); super(); end`.
#
# Bare `super` hands the parent whatever the method was called with; `super()`
# hands it nothing. A survivor means the forwarded arguments never reach an
# assertion — the parent ignores them, or nothing exercises what it does with
# them. ZsuperRemoval only turns the same node into `nil`, which asks whether
# the call happens rather than what it carries, and ExplicitSuperMutation works
# the other direction, on a super that already lists its arguments.
#
# The enclosing method must declare something to forward. With no parameters
# the two forms are identical, and so they are with only a block parameter:
# `super()` still passes the block along, so nothing would change.
class Evilution::Mutator::Operator::ForwardingSuperToExplicit < Evilution::Mutator::Base
  KEYWORD_LENGTH = "super".length
  private_constant :KEYWORD_LENGTH

  def visit_def_node(node)
    enclosing_methods.push(node)
    super
  ensure
    enclosing_methods.pop
  end

  def visit_forwarding_super_node(node)
    add_parentheses(node) if forwards_arguments?
    super
  end

  private

  # A stack, so a def nested in another method's body is answered with its own
  # parameters rather than the outer method's.
  def enclosing_methods
    @enclosing_methods ||= []
  end

  # Traversal always starts at the subject's own def, so a forwarding super is
  # never reached without one on the stack.
  def forwards_arguments?
    parameters = enclosing_methods.last.parameters
    return false if parameters.nil?

    !only_block_parameter?(parameters)
  end

  # `&blk` is forwarded either way, so it is not something `super()` drops.
  # Post-required parameters are not checked: a signature only has them after a
  # rest parameter, which the rest check already rejects.
  def only_block_parameter?(parameters)
    parameters.requireds.empty? && parameters.optionals.empty? && parameters.keywords.empty? &&
      parameters.rest.nil? && parameters.keyword_rest.nil?
  end

  # The parentheses are inserted right after the keyword rather than replacing
  # the node, whose span also covers a block written on the super.
  def add_parentheses(node)
    add_mutation(
      offset: node.location.start_offset + KEYWORD_LENGTH,
      length: 0,
      replacement: "()",
      node: node
    )
  end
end
