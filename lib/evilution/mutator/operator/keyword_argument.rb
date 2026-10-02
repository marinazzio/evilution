# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::KeywordArgument < Evilution::Mutator::Base
  def visit_def_node(node)
    params = node.parameters
    if params
      mutate_optional_keyword_defaults(params)
      mutate_optional_keyword_removal(params)
      mutate_keyword_rest_removal(node)
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

  def mutate_keyword_rest_removal(node)
    params = node.parameters
    kr = params.keyword_rest
    return unless kr.is_a?(Prism::KeywordRestParameterNode)
    return if anonymous_rest_used?(node.body)

    all_params = collect_all_params(params)
    if all_params.length < 2
      emit_remove_only_kr(kr)
    else
      emit_remove_kr_with_remaining(params, all_params, kr)
    end
  end

  # An anonymous `**` in the body (`bar(**)`, `{ ** }`) only parses while the
  # signature declares one, so removing it there would leave the body
  # unparseable. Finding one also tells the rest is anonymous: Ruby rejects it
  # next to a named rest. A named rest is safe to remove: without it the body
  # reads an undefined name, which parses and fails at runtime.
  def anonymous_rest_used?(body)
    return false if body.nil?

    uses_anonymous_rest?(body)
  end

  # A nested def is not searched: an anonymous `**` inside it belongs to that
  # method's own signature. Blocks and lambdas share the enclosing method's
  # parameters, so they are.
  def uses_anonymous_rest?(node)
    return false if node.is_a?(Prism::DefNode)
    return true if node.is_a?(Prism::AssocSplatNode) && node.value.nil?

    node.compact_child_nodes.any? { |child| uses_anonymous_rest?(child) }
  end

  def emit_remove_only_kr(kr)
    add_mutation(
      offset: kr.location.start_offset,
      length: kr.location.length,
      replacement: "",
      node: kr
    )
  end

  def emit_remove_kr_with_remaining(params, all_params, kr)
    remaining = all_params.reject { |p| p.equal?(kr) }
    add_mutation(
      offset: params.location.start_offset,
      length: params.location.length,
      replacement: remaining.map(&:slice).join(", "),
      node: kr
    )
  end

  def collect_all_params(params)
    [
      *params.requireds,
      *params.optionals,
      params.rest,
      *params.posts,
      *params.keywords,
      params.keyword_rest,
      params.block
    ].compact
  end
end
