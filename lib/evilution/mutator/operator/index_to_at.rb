# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::IndexToAt < Evilution::Mutator::Base
  def visit_call_node(node)
    if indexable?(node)
      add_mutation(
        offset: node.location.start_offset,
        length: node.location.length,
        replacement: "#{loc_text(node.receiver.location)}.at(#{loc_text(node.arguments.location)})",
        node: node
      )
    end

    super
  end

  private

  def loc_text(loc)
    @file_source.byteslice(loc.start_offset, loc.length)
  end

  # EV-pn5y / GH #1173: Hash has no #at method, so symbol/string keys (the
  # canonical Hash-key shape) must be skipped — otherwise the mutated source
  # crashes with NoMethodError instead of yielding a measurable mutation. We
  # still mutate integer literals and variable/expression keys (likely Array
  # indices); a false positive there is at worst a survived mutation, not a
  # runtime crash.
  def indexable?(node)
    node.name == :[] &&
      node.receiver &&
      node.arguments &&
      node.arguments.arguments.length == 1 &&
      !hash_key_shape?(node.arguments.arguments.first)
  end

  def hash_key_shape?(arg)
    arg.is_a?(Prism::SymbolNode) || arg.is_a?(Prism::StringNode)
  end
end
