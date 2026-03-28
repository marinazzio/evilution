# frozen_string_literal: true

require "prism"

require_relative "../ast"

class Evilution::AST::InheritanceScanner < Prism::Visitor
  attr_reader :inheritance

  def initialize
    @inheritance = {}
    @context = []
    super
  end

  def self.call(files)
    scanner = new
    files.each do |file|
      source = File.read(file)
      result = Prism.parse(source)
      next if result.failure?

      scanner.visit(result.value)
    rescue SystemCallError
      next
    end
    scanner.inheritance
  end

  def visit_class_node(node)
    class_name = qualified_name(node.constant_path)

    @inheritance[class_name] = (qualified_superclass(node.superclass) if node.superclass)

    @context.push(constant_name(node.constant_path))
    super
    @context.pop
  end

  def visit_module_node(node)
    @context.push(constant_name(node.constant_path))
    super
    @context.pop
  end

  private

  def qualified_name(node)
    name = constant_name(node)
    @context.empty? ? name : "#{@context.join("::")}::#{name}"
  end

  def qualified_superclass(node)
    name = constant_name(node)
    return name if name.include?("::")
    return name if @context.empty?

    "#{@context.join("::")}::#{name}"
  end

  def constant_name(node)
    if node.respond_to?(:full_name)
      node.full_name
    elsif node.respond_to?(:name)
      node.name.to_s
    else
      node.slice
    end
  end
end
