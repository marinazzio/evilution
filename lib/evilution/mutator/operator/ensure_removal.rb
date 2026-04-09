# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::EnsureRemoval < Evilution::Mutator::Base
  def visit_ensure_node(node)
    remove_start = line_start_after_newline(node.ensure_keyword_loc.start_offset)
    remove_end = line_start_after_newline(node.end_keyword_loc.start_offset)

    add_mutation(
      offset: remove_start,
      length: remove_end - remove_start,
      replacement: "",
      node: node
    )

    super
  end

  private

  def line_start_after_newline(offset)
    pos = offset
    pos -= 1 while pos.positive? && @file_source.getbyte(pos - 1) != 0x0A
    pos
  end
end
