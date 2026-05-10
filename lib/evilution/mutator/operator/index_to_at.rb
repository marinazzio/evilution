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

  # EV-pn5y / GH #1173: Hash has no #at method, so the symbol/string keys that
  # almost always indicate a Hash receiver are skipped here — otherwise the
  # mutated source crashes with NoMethodError instead of yielding a measurable
  # mutation. Integer literals and variable/expression keys are still mutated;
  # if the receiver in those cases turns out to be a Hash the mutation will
  # still raise NoMethodError at runtime, but those shapes are far rarer in
  # practice and the AST gives no reliable receiver-type signal to filter on.
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
