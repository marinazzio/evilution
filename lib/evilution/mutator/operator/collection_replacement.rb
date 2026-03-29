# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::CollectionReplacement < Evilution::Mutator::Base
  REPLACEMENTS = {
    map: [:each],
    each: [:map],
    select: [:reject],
    reject: [:select],
    flat_map: [:map],
    collect: [:each],
    sort: [:sort_by],
    sort_by: [:sort],
    find: [:detect],
    detect: [:find],
    any?: [:all?],
    all?: [:any?],
    count: [:length],
    length: [:count],
    pop: [:shift],
    shift: [:pop],
    push: [:unshift],
    unshift: [:push],
    each_key: [:each_value],
    each_value: [:each_key],
    assoc: [:rassoc],
    rassoc: [:assoc]
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
