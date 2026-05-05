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
    return line_start_before(node.subsequent.keyword_loc.start_offset) if node.subsequent

    loc = node.statements ? node.statements.location : node.keyword_loc
    loc.start_offset + loc.length
  end

  def line_start_before(offset)
    pos = offset - 1
    pos -= 1 while pos.positive? && @file_source.getbyte(pos) != 0x0A
    pos
  end
end
