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

  # Operators rewritten into a method call, since the method cannot be
  # swapped in as an operator (`a eql? b` does not parse). Ordering
  # comparisons collapse to the stricter equalities — `a < b` becomes
  # `a.eql?(b)` and `a.equal?(b)` — and `a =~ b` becomes `a.match?(b)`,
  # which returns a boolean and leaves `$~` / `$1` unset.
  EQUALITY_METHODS = %i[eql? equal?].freeze
  private_constant :EQUALITY_METHODS

  METHOD_REPLACEMENTS = {
    :< => EQUALITY_METHODS,
    :<= => EQUALITY_METHODS,
    :> => EQUALITY_METHODS,
    :>= => EQUALITY_METHODS,
    :=~ => [:match?]
  }.freeze
  private_constant :METHOD_REPLACEMENTS

  def visit_call_node(node)
    replace_operator(node)
    replace_with_methods(node)
    super
  end

  private

  def replace_operator(node)
    loc = node.message_loc

    REPLACEMENTS.fetch(node.name, []).each do |replacement|
      add_mutation(offset: loc.start_offset, length: loc.length, replacement: replacement.to_s, node: node)
    end
  end

  def replace_with_methods(node)
    methods = METHOD_REPLACEMENTS[node.name]
    return unless methods && (node.arguments in Prism::ArgumentsNode[arguments: [argument]])

    left = receiver_source(node.receiver)
    methods.each do |method|
      add_mutation(offset: node.start_offset, length: node.location.length,
                   replacement: "#{left}.#{method}(#{source_of(argument)})", node: node)
    end
  end
end
