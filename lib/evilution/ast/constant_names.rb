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
    names = []
    case node
    when Prism::ModuleNode, Prism::ClassNode
      const = node.constant_path.full_name
      qualified = nesting.any? && !const.include?("::") ? "#{nesting.join("::")}::#{const}" : const
      names << qualified
      names.concat(collect(node.body, nesting + [const])) if node.body
    when Prism::ProgramNode
      names.concat(collect(node.statements, nesting)) if node.statements
    when Prism::StatementsNode
      node.body.each { |child| names.concat(collect(child, nesting)) }
    end
    names
  end
end
