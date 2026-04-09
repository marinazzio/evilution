# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::IndexToFetch < Evilution::Mutator::Base
  def visit_call_node(node)
    if indexable?(node)
      receiver_source = byteslice_source(node.receiver.location.start_offset, node.receiver.location.length)
      arg_source = byteslice_source(node.arguments.location.start_offset, node.arguments.location.length)

      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "#{receiver_source}.fetch(#{arg_source})",
        node: node
      )
    end

    super
  end

  private

  def indexable?(node)
    node.name == :[] &&
      node.receiver &&
      node.arguments &&
      node.arguments.arguments.length == 1
  end
end
