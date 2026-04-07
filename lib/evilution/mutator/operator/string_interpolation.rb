# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::StringInterpolation < Evilution::Mutator::Base
  def visit_interpolated_string_node(node)
    mutate_embedded_statements(node)
    super
  end

  def visit_interpolated_symbol_node(node)
    mutate_embedded_statements(node)
    super
  end

  private

  def mutate_embedded_statements(node)
    node.parts.each do |part|
      next unless part.is_a?(Prism::EmbeddedStatementsNode)
      next if part.statements.nil? || part.statements.body.empty?

      stmt = part.statements
      add_mutation(
        offset: stmt.location.start_offset,
        length: stmt.location.length,
        replacement: "nil",
        node: part
      )
    end
  end
end
