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
    find: %i[detect first last],
    detect: %i[find first last],
    any?: %i[all? empty? none?],
    all?: %i[any? none?],
    count: [:length],
    length: [:count],
    pop: [:shift],
    shift: [:pop],
    push: [:unshift],
    unshift: [:push],
    each_key: [:each_value],
    each_value: [:each_key],
    assoc: [:rassoc],
    rassoc: [:assoc],
    grep: [:grep_v],
    grep_v: [:grep],
    take: [:drop],
    drop: [:take],
    min: %i[max first last],
    max: %i[min first last],
    min_by: %i[max_by first last],
    max_by: %i[min_by first last],
    compact: [:flatten],
    flatten: [:compact],
    zip: [:product],
    product: [:zip],
    first: [:last],
    last: [:first],
    keys: [:values],
    values: [:keys],
    sample: %i[first last],
    fetch: [:key?],
    at: %i[fetch key?],
    delete_if: [:reject],
    keep_if: [:select],
    filter_map: [:map],
    chunk: [:each],
    chunk_while: [:each],
    each_with_index: [:each],
    slice_when: [:each]
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
