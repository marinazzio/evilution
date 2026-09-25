# frozen_string_literal: true

require_relative "../operator"

# Drop one keyword argument at a call site: `build(name: "x", size: 2)`
# becomes `build(size: 2)` and `build(name: "x")`. Applies to any argument
# list — calls, `super` and `yield`.
#
# A survivor means the callee never consumes that keyword, or its default
# happens to match. argument_removal and argument_nil_substitution skip
# keyword arguments entirely.
#
# Only `key: value` pairs are dropped; a `**opts` double splat stays, though
# it still counts as a neighbour when removing the separator. A lone keyword
# that is the whole argument list is left to argument_list_removal.
class Evilution::Mutator::Operator::KeywordArgumentRemoval < Evilution::Mutator::Base
  def visit_arguments_node(node)
    node.arguments.each_with_index do |argument, index|
      next unless argument.is_a?(Prism::KeywordHashNode)

      drop_keywords(argument, index.zero? ? nil : node.arguments[index - 1])
    end

    super
  end

  private

  def drop_keywords(hash, previous_argument)
    elements = hash.elements
    return if elements.length == 1 && previous_argument.nil?

    elements.each_with_index do |element, index|
      next unless element.is_a?(Prism::AssocNode)

      drop_element(element, elements[index + 1], index.zero? ? previous_argument : elements[index - 1])
    end
  end

  # Cut from the element to the next one, or — for the last element — from
  # the end of whatever precedes it, so the separating comma goes too.
  def drop_element(element, following, preceding)
    start, finish = following ? [element.start_offset, following.start_offset] : [preceding.end_offset, element.end_offset]

    add_mutation(offset: start, length: finish - start, replacement: "", node: element, skip_unparseable: true)
  end
end
