# frozen_string_literal: true

require_relative "../operator"

# Replaces a method-call argument with its receiver: `fn(x.attr)` -> `fn(x)`.
# High-signal for log payloads, structured-data construction, and API
# request bodies where a method call on a local variable / param appears in
# argument position. Covered byte-wise by `MethodCallRemoval` already; this
# operator surfaces the same byte change under a more specific name so the
# argument-substitution pattern is legible in mutation output.
#
# Fires for:
# - positional / keyword arguments of any CallNode
# - hash values inside HashNode / KeywordHashNode (incl. inside call args)
# - array elements inside ArrayNode
class Evilution::Mutator::Operator::ArgumentMethodCallReplacement < Evilution::Mutator::Base
  def visit_call_node(node)
    node.arguments.arguments.each { |arg| try_replace(arg) } if node.arguments

    super
  end

  def visit_array_node(node)
    node.elements.each { |element| try_replace(element) }
    super
  end

  def visit_hash_node(node)
    process_assocs(node.elements)
    super
  end

  def visit_keyword_hash_node(node)
    process_assocs(node.elements)
    super
  end

  private

  def process_assocs(elements)
    elements.each do |assoc|
      next unless assoc.is_a?(Prism::AssocNode)

      try_replace(assoc.value)
    end
  end

  def try_replace(value)
    return unless value.is_a?(Prism::CallNode)
    return unless value.receiver

    add_mutation(
      offset: value.location.start_offset,
      length: value.location.length,
      replacement: value.receiver.slice,
      node: value
    )
  end
end
