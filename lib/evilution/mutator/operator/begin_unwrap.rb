# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BeginUnwrap < Evilution::Mutator::Base
  def visit_begin_node(node)
    return super if node.rescue_clause || node.else_clause || node.ensure_clause
    return super if node.statements.nil?
    return super if node.begin_keyword_loc.nil?

    body_text = @file_source.byteslice(node.statements.location.start_offset, node.statements.location.length)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: body_text,
      node: node
    )

    super
  end
end
