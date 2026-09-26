# frozen_string_literal: true

require_relative "../operator"

# Swap a constructor for a sibling on the same receiver constant:
# `Date.parse(value)` becomes `Date.iso8601(value)`, `Date.strptime(value)`,
# `Date.rfc2822(value)` and the rest. Keyed on receiver and selector, which
# the plain selector tables cannot express — `JSON.parse` is untouched.
#
# `parse` accepts almost any date-like string; the siblings accept one
# format (strptime's default is ISO 8601) or, like `jd` / `civil`, numbers
# only. A survivor means the tests only ever feed input every parser agrees
# on, so an overly lenient parse goes unnoticed.
#
# Only the constant itself (`Date`, `::Date`) matches, not a namespaced
# `Acme::Date`.
class Evilution::Mutator::Operator::ReceiverConstructorSwap < Evilution::Mutator::Base
  DATE_PARSE_SIBLINGS = %i[jd civil strptime iso8601 rfc3339 xmlschema rfc2822 rfc822 httpdate jisx0301].freeze
  private_constant :DATE_PARSE_SIBLINGS

  # receiver constant => { selector => replacements }. Time has no jd / civil
  # / rfc3339 / jisx0301, and its strptime requires a format argument.
  REPLACEMENTS = {
    Date: { parse: DATE_PARSE_SIBLINGS },
    DateTime: { parse: DATE_PARSE_SIBLINGS },
    Time: { parse: %i[iso8601 xmlschema rfc2822 rfc822 httpdate] }
  }.freeze
  private_constant :REPLACEMENTS

  def visit_call_node(node)
    replacements_for(node).each do |replacement|
      location = node.message_loc
      add_mutation(offset: location.start_offset, length: location.length, replacement: replacement.to_s, node: node)
    end
    super
  end

  private

  def replacements_for(node)
    selectors = REPLACEMENTS[receiver_constant(node.receiver)]
    selectors ? selectors.fetch(node.name, []) : []
  end

  def receiver_constant(receiver)
    case receiver
    when Prism::ConstantReadNode then receiver.name
    when Prism::ConstantPathNode then receiver.name if receiver.parent.nil?
    end
  end
end
