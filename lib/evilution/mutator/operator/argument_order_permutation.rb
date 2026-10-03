# frozen_string_literal: true

require_relative "../operator"

# Swap neighbouring positional arguments: `compute(a, b)` becomes
# `compute(b, a)`.
#
# A survivor means no example tells the two values apart — typically a test
# whose fixtures are symmetric, so the method could take them in either order
# unnoticed.
#
# Keyword arguments and a block argument stay where they are, and a splat
# keeps its neighbours in place: it stands for an unknown number of
# arguments, so a value swapped with it would not land where the original
# stood. Identical neighbours are not swapped, since that would reproduce the
# original call.
class Evilution::Mutator::Operator::ArgumentOrderPermutation < Evilution::Mutator::Base
  # `raise ArgumentError, "message"` reversed raises TypeError wherever it is
  # reached, which only shows that the line ran.
  RAISING_METHODS = %i[raise fail].freeze

  # Core methods that treat their arguments as an unordered set of
  # alternatives, so any order gives the same answer.
  ORDER_FREE_METHODS = %i[start_with? end_with?].freeze

  # Arguments whose position does not map to a single value.
  POSITIONLESS_TYPES = [Prism::SplatNode, Prism::ForwardingArgumentsNode].freeze

  def visit_call_node(node)
    swap_arguments(node) if swappable_call?(node)
    super
  end

  def visit_super_node(node)
    swap_arguments(node)
    super
  end

  def visit_yield_node(node)
    swap_arguments(node)
    super
  end

  private

  # The last argument of an index write is the value being stored, not a peer
  # of the index.
  def swappable_call?(node)
    return false if node.name == :[]=
    return false if ORDER_FREE_METHODS.include?(node.name)
    return false if set_literal?(node)

    !(node.receiver.nil? && RAISING_METHODS.include?(node.name))
  end

  # `Set[a, b]` builds a set, where the order of elements does not count.
  def set_literal?(node)
    return false unless node.name == :[]

    receiver = node.receiver
    case receiver
    when Prism::ConstantReadNode then receiver.name == :Set
    when Prism::ConstantPathNode then receiver.parent.nil? && receiver.name == :Set
    else false
    end
  end

  def swap_arguments(node)
    return if node.arguments.nil?

    positionals = node.arguments.arguments.grep_v(Prism::KeywordHashNode)
    positionals.each_cons(2) do |left, right|
      emit_swap(node, left, right) if swappable_pair?(left, right)
    end
  end

  def swappable_pair?(left, right)
    return false if [left, right].any? { |argument| POSITIONLESS_TYPES.include?(argument.class) }

    left.slice != right.slice
  end

  # Whatever separates the two arguments — the comma, line breaks, comments —
  # stays between them, so the call keeps its layout.
  def emit_swap(node, left, right)
    start_offset = left.location.start_offset
    end_offset = right.location.end_offset
    separator = byteslice_source(left.location.end_offset, right.location.start_offset - left.location.end_offset)

    add_mutation(
      offset: start_offset,
      length: end_offset - start_offset,
      replacement: "#{right.slice}#{separator}#{left.slice}",
      node: node
    )
  end
end
