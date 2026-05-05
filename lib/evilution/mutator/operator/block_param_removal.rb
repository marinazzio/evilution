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
    remove_start, remove_end = block_param_removal_range(node)

    add_mutation(
      offset: remove_start,
      length: remove_end - remove_start,
      replacement: "",
      node: node
    )
  end

  # Range covering ", &block" — from the comma before the block param to the end of the block param.
  def block_param_removal_range(node)
    params_loc = node.parameters.location
    block_loc = node.parameters.block.location
    params_text = @file_source.byteslice(params_loc.start_offset, params_loc.length)
    block_rel = block_loc.start_offset - params_loc.start_offset
    comma_pos = params_text.rindex(",", block_rel - 1)

    [params_loc.start_offset + comma_pos, block_loc.start_offset + block_loc.length]
  end
end
