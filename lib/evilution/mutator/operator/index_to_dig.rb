# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::IndexToDig < Evilution::Mutator::Base
  Chain = Data.define(:root, :args)
  private_constant :Chain

  def initialize(**options)
    super
    @consumed = Set.new
  end

  def visit_call_node(node)
    if chain_head?(node)
      chain = collect_chain(node)
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: dig_replacement(chain),
        node: node
      )
    end

    super
  end

  private

  def dig_replacement(chain)
    root_source = byteslice_source(chain.root.location.start_offset, chain.root.location.length)
    arg_sources = chain.args.map { |a| byteslice_source(a.location.start_offset, a.location.length) }
    "#{root_source}.dig(#{arg_sources.join(", ")})"
  end

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

    Chain.new(root: current, args: args)
  end
end
