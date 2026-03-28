# frozen_string_literal: true

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
    length: [:count]
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
