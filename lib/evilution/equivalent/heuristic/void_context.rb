# frozen_string_literal: true

require_relative "../heuristic"

class Evilution::Equivalent::Heuristic::VoidContext
  # Method pairs where the only difference is the return value.
  # In void context (return value unused), these are equivalent.
  VOID_EQUIVALENT_PAIRS = Set[
    Set[:each, :map],
    Set[:each, :reverse_each]
  ].freeze

  MATCHING_OPERATORS = Set["send_mutation", "collection_replacement"].freeze

  def match?(mutation)
    return false unless MATCHING_OPERATORS.include?(mutation.operator_name)

    pair = extract_method_pair(mutation.diff)
    return false unless pair
    return false unless VOID_EQUIVALENT_PAIRS.include?(pair)

    void_context?(mutation)
  end

  private

  def extract_method_pair(diff)
    removed = extract_method(diff, "- ")
    added = extract_method(diff, "+ ")
    return nil unless removed && added

    Set[removed.to_sym, added.to_sym]
  end

  def extract_method(diff, prefix)
    line = diff.split("\n").find { |l| l.start_with?(prefix) }
    return nil unless line

    match = line.match(/\.(\w+)(?:[\s({]|$)/)
    match && match[1]
  end

  def void_context?(mutation)
    node = mutation.subject.node
    return false unless node

    body = node.body
    return false unless body.is_a?(Prism::StatementsNode)

    statements = body.body
    call_node = find_call_at_line(statements, mutation.line)
    return false unless call_node

    # The call is in void context if:
    # 1. It's a direct statement (not wrapped in assignment)
    # 2. It's not the last statement in the method body
    statement_index = statements.index { |s| contains_line?(s, mutation.line) && direct_call?(s) }
    return false unless statement_index

    statement_index < statements.length - 1
  end

  def find_call_at_line(statements, line)
    statements.each do |stmt|
      return stmt if stmt.is_a?(Prism::CallNode) && stmt.location.start_line == line
    end
    nil
  end

  def direct_call?(statement)
    statement.is_a?(Prism::CallNode)
  end

  def contains_line?(node, line)
    line.between?(node.location.start_line, node.location.end_line)
  end
end
