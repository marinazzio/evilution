# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::IndexToDig < Evilution::Mutator::Base
  def initialize(**options)
    super
    @consumed = Set.new
  end

  def visit_call_node(node)
    if chain_head?(node)
      root, args = collect_chain(node)
      root_source = @file_source[root.location.start_offset, root.location.length]
      arg_sources = args.map { |a| @file_source[a.location.start_offset, a.location.length] }

      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "#{root_source}.dig(#{arg_sources.join(", ")})",
        node: node
      )
    end

    super
  end

  private

  def chain_head?(node)
    return false if @consumed.include?(node.object_id)
    return false unless single_arg_index?(node)
    return false unless single_arg_index?(node.receiver)

    true
  end

  def single_arg_index?(node)
    node.is_a?(Prism::CallNode) &&
      node.name == :[] &&
      node.receiver &&
      node.arguments &&
      node.arguments.arguments.length == 1
  end

  def collect_chain(node)
    args = []
    current = node

    while single_arg_index?(current)
      @consumed.add(current.object_id)
      args.unshift(current.arguments.arguments.first)
      current = current.receiver
    end

    [current, args]
  end
end
