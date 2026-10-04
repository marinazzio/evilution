# frozen_string_literal: true

require "prism"

require_relative "../operator"

# Drop an alias declaration from a class or module body: `alias length size`
# and `alias_method :count, :size` are removed.
#
# A survivor means no example calls the method by its alias, so the alias is
# a surface the suite never exercises — dead, or reached only where nothing
# asserts.
#
# Declarations sit in the class body, outside every method, where no subject
# reaches them. They are attributed to the first method of the innermost
# enclosing class, module or `class << self`, the way DataStructMember and
# MixinRemoval attribute theirs. An `alias_method` call inside a method is
# left to the generic call operators, and global-variable aliases
# (`alias $new $old`) are not method surface.
class Evilution::Mutator::Operator::AliasRemoval < Evilution::Mutator::Base
  def call(subject, filter: nil)
    @subject = subject
    @file_source = File.read(subject.file_path)
    @mutations = []
    @filter = filter

    declarations_for(subject).each { |declaration| remove(declaration) }
    @mutations
  end

  private

  def remove(declaration)
    add_mutation(
      offset: declaration.location.start_offset,
      length: declaration.location.length,
      replacement: "",
      node: declaration
    )
  end

  def declarations_for(subject)
    tree = self.class.parsed_tree_for(subject.file_path, @file_source)
    collector = DeclarationCollector.new
    collector.visit(tree)

    collector.declarations.filter_map do |declaration, scope|
      declaration if first_method_line(scope) == subject.line_number
    end
  end

  def first_method_line(scope)
    finder = FirstMethodFinder.new
    scope.compact_child_nodes.each { |child| finder.visit(child) }
    finder.line
  end

  # Collects alias declarations written in a class, module or singleton class
  # body, each paired with the innermost such scope. Method bodies are not
  # searched, and a top-level alias has no scope to attribute it to.
  class DeclarationCollector < Prism::Visitor
    attr_reader :declarations

    def initialize
      super
      @declarations = []
      @scopes = []
    end

    def visit_class_node(node)
      within(node) { super }
    end

    def visit_module_node(node)
      within(node) { super }
    end

    def visit_singleton_class_node(node)
      within(node) { super }
    end

    def visit_def_node(_node); end

    def visit_alias_method_node(node)
      record(node)
      super
    end

    # Blocks in the body (`included do ... end`) are searched too: an alias
    # there still belongs to the enclosing scope.
    def visit_call_node(node)
      record(node) if node.name == :alias_method && node.receiver.nil?
      super
    end

    private

    def record(node)
      @declarations << [node, @scopes.last] unless @scopes.empty?
    end

    def within(scope)
      @scopes.push(scope)
      yield
    ensure
      @scopes.pop
    end
  end

  # Finds the line of the first method written in a scope. Nested classes,
  # modules and singleton classes are not searched: their methods are subjects
  # of that inner scope.
  class FirstMethodFinder < Prism::Visitor
    attr_reader :line

    def visit_class_node(_node); end

    def visit_module_node(_node); end

    def visit_singleton_class_node(_node); end

    def visit_def_node(node)
      @line = node.location.start_line if @line.nil?
    end
  end
end
