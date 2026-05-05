# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::IndexToAt < Evilution::Mutator::Base
  def visit_call_node(node)
    if indexable?(node)
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "#{loc_text(node.receiver.location)}.at(#{loc_text(node.arguments.location)})",
        node: node
      )
    end

    super
  end

  private

  def loc_text(loc)
    @file_source.byteslice(loc.start_offset, loc.length)
  end

  def indexable?(node)
    node.name == :[] &&
      node.receiver &&
      node.arguments &&
      node.arguments.arguments.length == 1
  end
end
