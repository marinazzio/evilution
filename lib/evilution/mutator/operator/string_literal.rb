# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::StringLiteral < Evilution::Mutator::Base
  def initialize
    super
    @inside_heredoc = false
  end

  def visit_interpolated_string_node(node)
    if node.heredoc?
      @inside_heredoc = true
      super
      @inside_heredoc = false
    else
      super
    end
  end

  def visit_string_node(node)
    return super if node.heredoc? || @inside_heredoc

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
