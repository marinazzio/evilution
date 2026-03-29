# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::BangMethod < Evilution::Mutator::Base
  KNOWN_BANG_PAIRS = %i[
    sort map collect select reject uniq compact flatten
    shuffle reverse slice gsub sub strip chomp chop squeeze
    delete encode merge update save
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
