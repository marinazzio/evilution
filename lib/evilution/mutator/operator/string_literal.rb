# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::StringLiteral < Evilution::Mutator::Base
  def initialize(skip_heredoc_literals: false, **rest)
    super(**rest)
    @skip_heredoc_literals = skip_heredoc_literals
  end

  def visit_interpolated_string_node(node)
    return super unless node.heredoc?
    return if @skip_heredoc_literals

    node.parts.each do |part|
      next if part.is_a?(Prism::StringNode)

      visit(part)
    end
  end

  def visit_string_node(node)
    return super if node.heredoc?

    replacement = node.content.empty? ? '"mutation"' : '""'

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: replacement,
      node: node
    )

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "nil",
      node: node
    )

    super
  end
end
