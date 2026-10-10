# frozen_string_literal: true

require_relative "../operator"

# Widen what a rescue clause catches: `rescue KeyError` becomes
# `rescue StandardError` and `rescue Exception`.
#
# A survivor means no example raises a sibling error that has to get past
# the handler, so nothing shows the clause needs to be as narrow as it is.
#
# A bare `rescue` is `rescue StandardError`, so the two are never offered as
# mutants of each other; both go to `Exception` only. A clause that already
# names `Exception` cannot be widened. A rescue modifier (`x rescue y`) takes
# no class and is left alone.
class Evilution::Mutator::Operator::RescueClassWidening < Evilution::Mutator::Base
  WIDER = %w[StandardError Exception].freeze

  def visit_rescue_node(node)
    wider_than(node.exceptions).each { |name| widen(node, name) }
    super
  end

  private

  # The classes of WIDER above everything the clause lists.
  def wider_than(exceptions)
    listed = exceptions.map { |exception| exception.slice.delete_prefix("::") }
    listed = [WIDER.first] if listed.empty?
    widest = WIDER.rindex { |name| listed.include?(name) }

    widest ? WIDER.drop(widest + 1) : WIDER
  end

  def widen(node, name)
    exceptions = node.exceptions
    return insert_after_keyword(node, name) if exceptions.empty?

    offset = exceptions.first.location.start_offset
    add_mutation(offset:, length: exceptions.last.location.end_offset - offset, replacement: name, node:)
  end

  def insert_after_keyword(node, name)
    add_mutation(offset: node.keyword_loc.end_offset, length: 0, replacement: " #{name}", node:)
  end
end
