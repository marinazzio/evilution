# frozen_string_literal: true

require_relative "../operator"
require_relative "send_mutation"
require_relative "collection_replacement"

# Apply the call-site selector tables to a symbol block-pass: `map(&:to_s)`
# becomes `map(&:to_i)`, `map(&:first)` becomes `map(&:last)`.
#
# send_mutation and collection_replacement only see explicit calls, so a
# selector passed as `&:sym` was never swapped — only removed. This reads
# both tables live, so selectors added to them apply here too.
#
# Replacements that are Ruby aliases of the original (`collect` / `map`,
# `find` / `detect`, `select` / `filter`, `length` / `size` / `count`) are
# skipped: on the receivers these selectors are normally mapped over, the
# mutant behaves identically.
class Evilution::Mutator::Operator::SymbolToProcReplacement < Evilution::Mutator::Base
  TABLES = [
    Evilution::Mutator::Operator::SendMutation::REPLACEMENTS,
    Evilution::Mutator::Operator::CollectionReplacement::REPLACEMENTS
  ].freeze
  private_constant :TABLES

  ALIAS_GROUPS = [
    %i[map collect],
    %i[find detect],
    %i[select filter],
    %i[length size count]
  ].freeze
  private_constant :ALIAS_GROUPS

  def visit_block_argument_node(node)
    symbol = node.expression
    replace_selector(node, symbol) if symbol.is_a?(Prism::SymbolNode)
    super
  end

  private

  def replace_selector(node, symbol)
    selector = symbol.unescaped.to_sym
    location = symbol.value_loc

    replacements_for(selector).each do |replacement|
      add_mutation(
        offset: location.start_offset,
        length: location.length,
        replacement: replacement.to_s,
        node: node
      )
    end
  end

  def replacements_for(selector)
    aliases = ALIAS_GROUPS.find { |group| group.include?(selector) } || []
    TABLES.flat_map { |table| table.fetch(selector, []) }.uniq - aliases
  end
end
