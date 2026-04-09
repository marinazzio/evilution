# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::KeywordArgument < Evilution::Mutator::Base
  def visit_def_node(node)
    params = node.parameters
    if params
      mutate_optional_keyword_defaults(params)
      mutate_optional_keyword_removal(params)
      mutate_keyword_rest_removal(params)
    end

    super
  end

  private

  def mutate_optional_keyword_defaults(params)
    params.keywords.each do |kw|
      next unless kw.is_a?(Prism::OptionalKeywordParameterNode)

      name_loc = kw.name_loc
      kw_loc = kw.location

      add_mutation(
        offset: kw_loc.start_offset,
        length: kw_loc.length,
        replacement: byteslice_source(name_loc.start_offset, name_loc.end_offset - name_loc.start_offset),
        node: kw
      )
    end
  end

  def mutate_optional_keyword_removal(params)
    all_params = collect_all_params(params)
    return if all_params.length < 2

    params.keywords.each do |kw|
      next unless kw.is_a?(Prism::OptionalKeywordParameterNode)

      remaining = all_params.reject { |p| p.equal?(kw) }
      replacement = remaining.map(&:slice).join(", ")

      add_mutation(
        offset: params.location.start_offset,
        length: params.location.length,
        replacement: replacement,
        node: kw
      )
    end
  end

  def mutate_keyword_rest_removal(params)
    kr = params.keyword_rest
    return unless kr.is_a?(Prism::KeywordRestParameterNode)

    all_params = collect_all_params(params)

    if all_params.length < 2
      add_mutation(
        offset: kr.location.start_offset,
        length: kr.location.length,
        replacement: "",
        node: kr
      )
    else
      remaining = all_params.reject { |p| p.equal?(kr) }
      replacement = remaining.map(&:slice).join(", ")

      add_mutation(
        offset: params.location.start_offset,
        length: params.location.length,
        replacement: replacement,
        node: kr
      )
    end
  end

  def collect_all_params(params)
    result = []
    result.concat(params.requireds)
    result.concat(params.optionals)
    result << params.rest if params.rest
    result.concat(params.posts)
    result.concat(params.keywords)
    result << params.keyword_rest if params.keyword_rest
    result << params.block if params.block
    result
  end
end
