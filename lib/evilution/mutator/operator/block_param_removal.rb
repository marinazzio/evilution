# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BlockParamRemoval < Evilution::Mutator::Base
  def visit_def_node(node)
    return super unless node.parameters
    return super unless node.parameters.block

    if only_block_param?(node.parameters)
      remove_entire_params(node)
    else
      remove_block_param(node)
    end

    super
  end

  private

  def only_block_param?(params)
    params.requireds.empty? &&
      params.optionals.empty? &&
      params.keywords.empty? &&
      params.rest.nil? &&
      params.keyword_rest.nil?
  end

  def remove_entire_params(node)
    start_offset = node.lparen_loc.start_offset
    end_offset = node.rparen_loc.start_offset + node.rparen_loc.length
    add_mutation(
      offset: start_offset,
      length: end_offset - start_offset,
      replacement: "",
      node: node
    )
  end

  def remove_block_param(node)
    block_loc = node.parameters.block.location
    params_text = @file_source.byteslice(node.parameters.location.start_offset, node.parameters.location.length)
    block_rel = block_loc.start_offset - node.parameters.location.start_offset

    # Find the comma before the block param and remove ", &block"
    comma_pos = params_text.rindex(",", block_rel - 1)
    remove_start = node.parameters.location.start_offset + comma_pos
    remove_end = block_loc.start_offset + block_loc.length

    add_mutation(
      offset: remove_start,
      length: remove_end - remove_start,
      replacement: "",
      node: node
    )
  end
end
