# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::SendMutation < Evilution::Mutator::Base
  REPLACEMENTS = {
    flat_map: [:map],
    map: [:flat_map],
    collect: [:map],
    public_send: [:send],
    send: [:public_send],
    gsub: [:sub],
    sub: [:gsub],
    detect: [:find],
    find: [:detect],
    each_with_object: [:inject],
    inject: %i[each_with_object sum],
    reverse_each: [:each],
    each: [:reverse_each],
    length: [:size],
    size: [:length],
    values_at: [:fetch_values],
    fetch_values: [:values_at],
    sum: [:inject],
    count: [:size],
    select: [:filter],
    filter: [:select],
    to_s: [:to_i],
    to_i: [:to_s],
    to_f: [:to_i],
    to_a: [:to_h],
    to_h: [:to_a],
    downcase: [:upcase],
    upcase: [:downcase]
  }.freeze

  def visit_call_node(node)
    replacements = REPLACEMENTS[node.name]
    return super unless replacements
    return super unless node.receiver

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
