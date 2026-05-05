# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BeginUnwrap < Evilution::Mutator::Base
  def visit_begin_node(node)
    return super unless unwrappable?(node)

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: body_text(node),
      node: node
    )

    super
  end

  private

  def unwrappable?(node)
    return false if node.rescue_clause || node.else_clause || node.ensure_clause
    return false if node.statements.nil?
    return false if node.begin_keyword_loc.nil?

    true
  end

  def body_text(node)
    loc = node.statements.location
    @file_source.byteslice(loc.start_offset, loc.length)
  end
end
