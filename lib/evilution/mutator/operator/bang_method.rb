# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BangMethod < Evilution::Mutator::Base
  # Every standard-library method with an in-place bang twin (String, Array,
  # Hash, Set as of Ruby 4.0), plus `update` / `save` for ActiveRecord.
  KNOWN_BANG_PAIRS = %i[
    sort sort_by map collect select filter reject uniq compact flatten
    shuffle reverse rotate slice
    gsub sub tr tr_s strip lstrip rstrip chomp chop squeeze delete
    delete_prefix delete_suffix capitalize downcase upcase swapcase
    scrub encode unicode_normalize succ next
    merge transform_keys transform_values
    update save
  ].to_set.freeze

  def visit_call_node(node)
    return super unless node.receiver

    loc = node.message_loc
    return super unless loc

    name = node.name.to_s

    if name.end_with?("!")
      generate_non_bang(node, loc, name)
    elsif KNOWN_BANG_PAIRS.include?(node.name)
      generate_bang(node, loc, name)
    end

    super
  end

  private

  def generate_non_bang(node, loc, name)
    add_mutation(
      offset: loc.start_offset,
      length: loc.length,
      replacement: name.chomp("!"),
      node: node
    )
  end

  def generate_bang(node, loc, name)
    add_mutation(
      offset: loc.start_offset,
      length: loc.length,
      replacement: "#{name}!",
      node: node
    )
  end
end
