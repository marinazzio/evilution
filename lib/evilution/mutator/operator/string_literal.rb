# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::StringLiteral < Evilution::Mutator::Base
  def initialize(skip_heredoc_literals: false, **rest)
    super(**rest)
    @skip_heredoc_literals = skip_heredoc_literals
  end

  def visit_interpolated_string_node(node)
    if node.heredoc?
      return if @skip_heredoc_literals

      node.parts.each do |part|
        next if part.is_a?(Prism::StringNode)

        visit(part)
      end
      return
    end

    # Adjacent-string concatenation — both `"foo" "bar"` and the line-continued
    # form `"foo" \\\n "bar"` — lands in an InterpolatedStringNode whose parts
    # are all StringNodes. Mutating chunks individually splices the wrong span:
    # for the continued form Ruby treats `nil \\\n "rest"` as a confusing
    # parse rather than a clean nil; for both forms the result is one StringNode
    # plus an orphaned adjacent literal, not a meaningful mutation of the whole
    # expression. Replace the entire concatenation in one shot instead.
    if adjacent_string_concat?(node)
      emit_string_mutations(node)
      return
    end

    super
  end

  def visit_string_node(node)
    return super if node.heredoc?

    emit_string_mutations(node)

    super
  end

  private

  def adjacent_string_concat?(node)
    node.parts.length > 1 && node.parts.all?(Prism::StringNode)
  end

  def emit_string_mutations(node)
    empty = node_content_empty?(node)
    replacement = empty ? '"mutation"' : '""'

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
  end

  def node_content_empty?(node)
    return node.content.empty? if node.is_a?(Prism::StringNode)

    node.parts.all? { |part| part.is_a?(Prism::StringNode) && part.content.empty? }
  end
end
