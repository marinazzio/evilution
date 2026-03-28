# frozen_string_literal: true

class Evilution::Mutator::Operator::ComparisonReplacement < Evilution::Mutator::Base
  REPLACEMENTS = {
    :> => %i[>= == <],
    :< => %i[<= == >],
    :>= => %i[> == <=],
    :<= => %i[< == >=],
    :== => [:!=],
    :!= => [:==]
  }.freeze

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

    super
  end
end
