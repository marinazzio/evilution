# frozen_string_literal: true

require_relative "../operator"
require_relative "../rescue_handlers"

# Move the else clause of a rescue into the code it guards, keeping the rescue:
#
#   begin                    begin
#     fetch(id)                fetch(id)
#   rescue StandardError ->    notify
#     default                rescue StandardError
#   else                       default
#     notify                 end
#   end
#
# The else code still runs only when the body succeeded; the one thing that
# changes is that an error it raises is now caught by the rescue, where an
# else clause is not protected. A survivor means no test lets the else code
# fail in a way the rescue would swallow.
#
# Only a rescue with at least one broad clause — a bare `rescue`, or one
# naming StandardError or Exception — is mutated. Under a rescue for specific
# classes the moved code changes behaviour only if it raises one of them,
# which it rarely does, so those mutants would mostly survive without saying
# anything. An empty else clause and a rescue around an empty body are
# skipped; ensure clauses and every rescue clause stay as written.
class Evilution::Mutator::Operator::RescueElseConcatenation < Evilution::Mutator::Base
  BROAD_EXCEPTIONS = %w[StandardError ::StandardError Exception ::Exception].freeze

  def visit_begin_node(node)
    else_clause = node.else_clause
    move_else(node, else_clause) if node.statements && else_clause && else_clause.statements && broad_rescue?(node)
    super
  end

  private

  def broad_rescue?(node)
    Evilution::Mutator::RescueHandlers.new(node).clauses.any? do |clause|
      clause.exceptions.empty? || clause.exceptions.any? { |exception| BROAD_EXCEPTIONS.include?(exception.slice) }
    end
  end

  # One edit from the end of the body to the end of the else body: the else
  # statements go first, then the rescue clauses as they were, with the
  # whitespace (and a one-line `;`) that led into `else` trimmed off.
  def move_else(node, else_clause)
    body_end = node.statements.location.end_offset
    continuation = Evilution::Mutator::RescueHandlers.continuation(@file_source, node.statements)

    add_mutation(
      offset: body_end,
      length: else_clause.statements.location.end_offset - body_end,
      replacement: "#{continuation}#{else_clause.statements.slice}#{rescue_clauses_text(body_end, else_clause)}",
      node: else_clause
    )
  end

  def rescue_clauses_text(body_end, else_clause)
    byteslice_source(body_end, else_clause.else_keyword_loc.start_offset - body_end).rstrip.delete_suffix(";")
  end
end
