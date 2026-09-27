# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::ComparisonReplacement < Evilution::Mutator::Base
  REPLACEMENTS = {
    :> => %i[>= == <],
    :< => %i[<= == >],
    :>= => %i[> == <=],
    :<= => %i[< == >=],
    :== => [:!=],
    :!= => [:==]
  }.freeze

  # Ordering comparisons also collapse to the stricter equalities, which
  # cannot be swapped in as an operator: `a < b` becomes `a.eql?(b)` and
  # `a.equal?(b)`, separating the type-strict and identity checks from `==`.
  ORDERING = %i[< <= > >=].to_set.freeze
  private_constant :ORDERING

  EQUALITY_METHODS = %i[eql? equal?].freeze
  private_constant :EQUALITY_METHODS

  def visit_call_node(node)
    replacements = REPLACEMENTS[node.name]
    return super unless replacements

    loc = node.message_loc
    return super unless loc

    replacements.each do |replacement|
      add_mutation(
        offset: loc.start_offset,
        length: loc.length,
        replacement: replacement.to_s,
        node: node
      )
    end
    replace_with_equality_methods(node) if ORDERING.include?(node.name)

    super
  end

  private

  def replace_with_equality_methods(node)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [argument]]

    left = receiver_source(node.receiver)
    EQUALITY_METHODS.each do |method|
      add_mutation(offset: node.start_offset, length: node.location.length,
                   replacement: "#{left}.#{method}(#{source_of(argument)})", node: node)
    end
  end
end
