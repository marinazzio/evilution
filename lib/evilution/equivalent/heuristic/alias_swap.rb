# frozen_string_literal: true

require_relative "../heuristic"

class Evilution::Equivalent::Heuristic::AliasSwap
  ALIAS_PAIRS = Set[
    Set[:detect, :find],
    Set[:length, :size],
    Set[:collect, :map],
    Set[:count, :length],
    Set[:count, :size]
  ].freeze

  MATCHING_OPERATORS = Set["send_mutation", "collection_replacement"].freeze

  def match?(mutation)
    return false unless MATCHING_OPERATORS.include?(mutation.operator_name)

    diff = mutation.diff
    removed = extract_method(diff, "- ")
    added = extract_method(diff, "+ ")
    return false unless removed && added

    pair = Set[removed.to_sym, added.to_sym]
    ALIAS_PAIRS.include?(pair)
  end

  private

  def extract_method(diff, prefix)
    line = diff.split("\n").find { |l| l.start_with?(prefix) }
    return nil unless line

    match = line.match(/\.(\w+)(?:[\s(]|$)/)
    match && match[1]
  end
end
