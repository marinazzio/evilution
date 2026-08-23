# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::CaseWhen < Evilution::Mutator::Base
  def visit_case_node(node)
    remove_when_branches(node)
    replace_when_bodies(node)
    raise_in_empty_when_bodies(node)
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
      next if empty_body?(when_node)

      add_mutation(
        offset: when_node.statements.location.start_offset,
        length: when_node.statements.location.length,
        replacement: "nil",
        node: when_node
      )
    end
  end

  # An empty arm is a deliberate no-op, so there is no body to blank out --
  # dropping the arm entirely is indistinguishable from falling through to a
  # missing else. Inserting a raise is what proves the arm was selected.
  def raise_in_empty_when_bodies(node)
    node.conditions.each do |when_node|
      next unless empty_body?(when_node)

      indent = " " * (indentation_of(when_node.keyword_loc.start_offset) + 2)

      add_mutation(
        offset: body_insert_offset(when_node),
        length: 0,
        replacement: "\n#{indent}raise",
        node: when_node
      )
    end
  end

  def empty_body?(when_node)
    statements = when_node.statements
    statements.nil? || statements.body.empty?
  end

  # `when 1, 2` puts the body after the last condition; `when 1 then` after the
  # keyword. Prism reports a nil then_keyword_loc when the form omits it.
  def body_insert_offset(when_node)
    then_keyword_loc = when_node.then_keyword_loc
    location = then_keyword_loc.nil? ? when_node.conditions.last.location : then_keyword_loc

    location.start_offset + location.length
  end

  def indentation_of(offset)
    offset - line_start_byte(@file_source, offset)
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
