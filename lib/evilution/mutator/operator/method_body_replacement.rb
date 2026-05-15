# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::MethodBodyReplacement < Evilution::Mutator::Base
  ALWAYS_SAFE_REPLACEMENTS = %w[nil self].freeze
  SUPER_REPLACEMENT = "super"

  def visit_def_node(node)
    target = mutation_target(node.body)
    if target
      replacements = ALWAYS_SAFE_REPLACEMENTS.dup
      replacements << SUPER_REPLACEMENT if body_calls_super?(target)

      replacements.each do |replacement|
        add_mutation(
          offset: target.location.start_offset,
          length: target.location.length,
          replacement: replacement,
          node: node
        )
      end
    end

    super
  end

  private

  # A method-level rescue/ensure (`def foo; stmts; rescue; ...; end`) makes
  # node.body a BeginNode whose location spans the entire `def...end` — the
  # `def` keyword and matching `end` included. Replacing that range obliterates
  # the method framing, leaving the replacement (`nil`/`self`/`super`) dangling
  # at the enclosing scope. The replaceable region is only the leading
  # statements; returns nil when there are none (rescue/ensure-only body).
  def mutation_target(body)
    return body unless body.is_a?(Prism::BeginNode)

    body.statements
  end

  # The bare-super replacement raises NoMethodError at runtime when the enclosing
  # class has no parent implementation of the method. We emit it only when the
  # original body already calls super, using that as a heuristic that a super
  # target is intended in this context.
  def body_calls_super?(node)
    return true if node.is_a?(Prism::SuperNode) || node.is_a?(Prism::ForwardingSuperNode)

    node.child_nodes.any? { |child| child && body_calls_super?(child) }
  end
end
