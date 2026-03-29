# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::RescueRemoval < Evilution::Mutator::Base
  def visit_rescue_node(node)
    remove_start = line_start_before(node.keyword_loc.start_offset)
    remove_end = rescue_end_offset(node)

    add_mutation(
      offset: remove_start,
      length: remove_end - remove_start,
      replacement: "",
      node: node
    )

    super
  end

  private

  def rescue_end_offset(node)
    if node.subsequent
      line_start_before(node.subsequent.keyword_loc.start_offset)
    elsif node.statements
      node.statements.location.start_offset + node.statements.location.length
    else
      node.keyword_loc.start_offset + node.keyword_loc.length
    end
  end

  def line_start_before(offset)
    pos = offset - 1
    pos -= 1 while pos.positive? && @file_source[pos] != "\n"
    pos
  end
end
