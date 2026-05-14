# frozen_string_literal: true

require_relative "../heuristic"

class Evilution::Equivalent::Heuristic::DeadCode
  # Both operators produce statement-deletion-shaped edits. MutationPlanner
  # dedupes by (file_path, mutated_source); whichever operator is registered
  # first surfaces its name on the surviving mutation. Classify equivalence
  # by edit shape, not by operator label, so dead-code classification holds
  # regardless of registry order (EV-74e3 PR #1236 review).
  STATEMENT_DELETION_OPERATORS = %w[statement_deletion last_expression_removal].to_set.freeze

  def match?(mutation)
    return false unless STATEMENT_DELETION_OPERATORS.include?(mutation.operator_name)

    node = mutation.subject.node
    return false unless node

    body = node.body
    return false unless body.is_a?(Prism::StatementsNode)

    statements = body.body
    unreachable_lines = find_unreachable_lines(statements)
    unreachable_lines.include?(mutation.line)
  end

  private

  def find_unreachable_lines(statements)
    lines = Set.new
    found_unconditional_return = false

    statements.each do |stmt|
      if found_unconditional_return
        collect_lines(stmt, lines)
      elsif unconditional_return?(stmt)
        found_unconditional_return = true
      end
    end

    lines
  end

  def unconditional_return?(node)
    node.is_a?(Prism::ReturnNode) ||
      (node.is_a?(Prism::CallNode) && node.name == :raise)
  end

  def collect_lines(node, lines)
    start_line = node.location.start_line
    end_line = node.location.end_line
    (start_line..end_line).each { |l| lines.add(l) }
  end
end
