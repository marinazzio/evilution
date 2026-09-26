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
    to_s: %i[to_i to_str],
    to_i: %i[to_s to_int],
    to_f: [:to_i],
    to_a: %i[to_h to_ary],
    to_h: %i[to_a to_hash],
    downcase: [:upcase],
    upcase: [:downcase],
    strip: %i[lstrip rstrip],
    lstrip: [:strip],
    rstrip: [:strip],
    chomp: [:chop],
    chop: [:chomp],
    bytes: [:chars],
    chars: [:bytes],
    start_with?: [:end_with?],
    end_with?: [:start_with?],
    ceil: [:floor],
    floor: [:ceil],
    transform_keys: [:transform_values],
    transform_values: [:transform_keys],
    append: [:prepend],
    prepend: [:append],
    reverse_merge: [:merge]
  }.freeze

  # Swapped only when called with exactly one argument. Kept out of
  # REPLACEMENTS, which symbol_to_proc_replacement also reads: `&:method`
  # always calls with none, and a zero-argument `method` is usually an
  # accessor such as `request.method` (the HTTP verb), not Object#method.
  ONE_ARGUMENT_REPLACEMENTS = {
    method: [:public_method]
  }.freeze

  def visit_call_node(node)
    replacements = replacements_for(node)
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

  private

  def replacements_for(node)
    REPLACEMENTS.fetch(node.name) do
      ONE_ARGUMENT_REPLACEMENTS[node.name] if node.arguments && node.arguments.arguments.length == 1
    end
  end
end
