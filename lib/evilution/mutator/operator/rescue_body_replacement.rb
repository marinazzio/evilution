# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::RescueBodyReplacement < Evilution::Mutator::Base
  def visit_rescue_node(node)
    generate_nil_replacement(node)
    generate_raise_replacement(node)

    super
  end

  private

  def generate_nil_replacement(node)
    return if node.statements.nil?

    body_loc = node.statements.location
    indent = " " * indentation_of(body_loc.start_offset)

    add_mutation(
      offset: body_loc.start_offset,
      length: body_loc.length,
      replacement: "#{indent}nil".lstrip,
      node: node
    )
  end

  def generate_raise_replacement(node)
    return if bare_raise?(node)

    if node.statements.nil?
      insert_raise_into_empty(node)
    else
      replace_body_with_raise(node)
    end
  end

  def replace_body_with_raise(node)
    body_loc = node.statements.location
    indent = " " * indentation_of(body_loc.start_offset)

    add_mutation(
      offset: body_loc.start_offset,
      length: body_loc.length,
      replacement: "#{indent}raise".lstrip,
      node: node
    )
  end

  def insert_raise_into_empty(node)
    insert_offset = rescue_line_end(node)
    indent = " " * (indentation_of(node.keyword_loc.start_offset) + 2)

    add_mutation(
      offset: insert_offset,
      length: 0,
      replacement: "\n#{indent}raise",
      node: node
    )
  end

  def bare_raise?(node)
    return false if node.statements.nil?

    body = node.statements.body
    body.length == 1 &&
      body.first.is_a?(Prism::CallNode) &&
      body.first.name == :raise &&
      body.first.arguments.nil? &&
      body.first.receiver.nil?
  end

  def rescue_line_end(node)
    if node.reference
      node.reference.location.start_offset + node.reference.location.length
    elsif node.exceptions.any?
      last_exc = node.exceptions.last
      last_exc.location.start_offset + last_exc.location.length
    else
      node.keyword_loc.start_offset + node.keyword_loc.length
    end
  end

  def indentation_of(offset)
    pos = offset - 1
    col = 0
    while pos >= 0 && @file_source[pos] != "\n"
      col += 1
      pos -= 1
    end
    col
  end
end
