# frozen_string_literal: true

require "prism"
require_relative "../ast"

# Walks a Prism AST and returns every class/module constant declared, nested
# names rendered fully-qualified (e.g. "Foo::Bar"). Order is source order:
# outer declarations precede their nested children.
class Evilution::AST::ConstantNames
  def call(source)
    result = Prism.parse(source)
    return [] if result.failure?

    collect(result.value)
  end

  private

  def collect(node, nesting = [])
    case node
    when Prism::ModuleNode, Prism::ClassNode then collect_class(node, nesting)
    when Prism::ProgramNode then collect_program(node, nesting)
    when Prism::StatementsNode then collect_statements(node, nesting)
    else []
    end
  end

  def collect_class(node, nesting)
    const = node.constant_path.full_name
    qualified = qualify(const, nesting)
    return [qualified] if node.body.nil?

    [qualified] + collect(node.body, nesting + [const])
  end

  def collect_program(node, nesting)
    return [] if node.statements.nil?

    collect(node.statements, nesting)
  end

  def collect_statements(node, nesting)
    node.body.flat_map { |child| collect(child, nesting) }
  end

  def qualify(const, nesting)
    return const if nesting.empty? || const.include?("::")

    "#{nesting.join("::")}::#{const}"
  end
end
