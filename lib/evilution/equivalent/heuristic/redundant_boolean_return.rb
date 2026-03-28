# frozen_string_literal: true

require_relative "../heuristic"

class Evilution::Equivalent::Heuristic::RedundantBooleanReturn
  BOOLEAN_SWAP_PATTERN = /^- .*return (true|false)\n\+ .*return (true|false)$/

  def match?(mutation)
    return false unless mutation.operator_name == "boolean_literal_replacement"
    return false unless mutation.diff.match?(BOOLEAN_SWAP_PATTERN)

    subject = mutation.subject
    return false unless subject.respond_to?(:node)

    node = subject.node
    return false unless node
    return false unless node.is_a?(Prism::DefNode)

    node.name.end_with?("?")
  end
end
