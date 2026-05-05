# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::CaseWhen < Evilution::Mutator::Base
  def visit_case_node(node)
    remove_when_branches(node)
    replace_when_bodies(node)
    remove_else_branch(node)

    super
  end

  private

  def remove_when_branches(node)
    return if node.conditions.length < 2

    node.conditions.each do |when_node|
      add_mutation(
        offset: when_node.location.start_offset,
        length: when_node.location.length,
        replacement: "",
        node: when_node
      )
    end
  end

  def replace_when_bodies(node)
    node.conditions.each do |when_node|
      next if when_node.statements.nil? || when_node.statements.body.empty?

      add_mutation(
        offset: when_node.statements.location.start_offset,
        length: when_node.statements.location.length,
        replacement: "nil",
        node: when_node
      )
    end
  end

  def remove_else_branch(node)
    else_clause = node.else_clause
    return if else_clause.nil? || else_clause.statements.nil?

    start_offset = else_clause.else_keyword_loc.start_offset
    stmts_loc = else_clause.statements.location
    end_offset = stmts_loc.start_offset + stmts_loc.length

    add_mutation(
      offset: start_offset,
      length: end_offset - start_offset,
      replacement: "",
      node: else_clause
    )
  end
end
