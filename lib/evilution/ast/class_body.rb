# frozen_string_literal: true

require "prism"
require_relative "../ast"
require_relative "value_object_definition"

# The body of a class, module or `class << self`, or the block of a
# value-object definition (`Data.define(:a) do ... end`), which is the body of
# the class it defines: the code written outside every method, where no method
# subject reaches it.
#
# Operators that mutate such code attribute their mutants to one method, so
# each mutant has exactly one subject. That method is the scope's anchor: the
# first method written in the scope, in source order. Blocks of the body
# (`included do ... end`) are searched, nested scopes are not: their methods
# anchor the inner scope, and their code is attributed to it.
#
# A scope with no method of its own borrows the anchor of the first singleton
# class in its body that has one, so a class whose methods all sit in
# `class << self` is still reached. It never borrows from a value-object
# block: those methods belong to the class the block defines, and a mutant
# labelled with one of them would point at code it does not contain. A scope
# left without an anchor is listed by .unanchored_in, for operators whose
# code has a subject of its own to fall back on (a constant assignment).
class Evilution::AST::ClassBody
  SCOPES = [Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

  # The location that closes each kind of conditional or loop.
  CLOSINGS = {
    Prism::IfNode => :end_keyword_loc,
    Prism::UnlessNode => :end_keyword_loc,
    Prism::ElseNode => :end_keyword_loc,
    Prism::WhileNode => :closing_loc,
    Prism::UntilNode => :closing_loc
  }.freeze

  attr_reader :node

  # The bodies anchored at the method starting on the given line, outermost
  # first. A method anchors its own scope, and with it any enclosing scope
  # that borrows from it.
  def self.anchored_at(tree, line)
    bodies_in(tree).select { |body| body.anchor_line == line }
  end

  # The bodies with no anchor, outermost first: no method of their own, and
  # none to borrow.
  def self.unanchored_in(tree)
    bodies_in(tree).select { |body| body.anchor_line.nil? }
  end

  # Every body of the tree, outermost first. The operators ask this of a
  # file's tree once for each of its subjects, so the bodies of the last tree
  # walked are kept until another is asked about or .clear! is called.
  def self.bodies_in(tree)
    return @bodies if @tree.equal?(tree)

    @bodies = scopes_in(tree).map { |scope| new(scope) }.freeze
    @tree = tree
    @bodies
  end

  def self.clear!
    @tree = nil
    @bodies = nil
  end

  def self.scopes_in(node)
    node.compact_child_nodes.flat_map do |child|
      nested = scopes_in(child)
      scope?(node, child) ? [child, *nested] : nested
    end
  end

  # Whether the child of the node opens a scope of its own.
  def self.scope?(node, child)
    SCOPES.include?(child.class) || (child.is_a?(Prism::BlockNode) && Evilution::AST::ValueObjectDefinition.match?(node))
  end

  # Whether the child of the node belongs to something else: a method, or
  # another scope.
  def self.opaque?(node, child)
    child.is_a?(Prism::DefNode) || scope?(node, child)
  end

  private_class_method :scopes_in, :bodies_in

  def initialize(node)
    @node = node
  end

  def anchor_line
    return @anchor_line if defined?(@anchor_line)

    @anchor_line = find_anchor_line
  end

  # The statements of the body the block selects, each one removable: cut
  # out, it leaves code that still parses. Methods and nested scopes are
  # neither offered nor searched, and neither is a statement guarded by a
  # modifier (`include Foo if legacy?`) or an expression used as a value.
  def declarations(&)
    body = @node.body
    return [] unless body

    statements_in(body, removable: body.is_a?(Prism::StatementsNode)).select(&)
  end

  private

  def find_anchor_line
    first_method = contents.find { |child| child.is_a?(Prism::DefNode) }
    return first_method.location.start_line if first_method

    singleton_classes = contents.grep(Prism::SingletonClassNode)
    singleton_classes.filter_map { |scope| self.class.new(scope).anchor_line }.first
  end

  # Every node written in the scope, in source order, down to the methods and
  # nested scopes, which are listed but not entered. The scope's own header
  # (its name, its superclass expression) is not part of the body.
  def contents
    @contents ||= @node.body ? descend(@node.body) : []
  end

  def statements_in(node, removable:)
    node.compact_child_nodes.flat_map do |child|
      next [] if self.class.opaque?(node, child)

      nested = statements_in(child, removable: child.is_a?(Prism::StatementsNode) && !modifier?(node))
      removable ? [child, *nested] : nested
    end
  end

  # A conditional or loop written without its closing keyword: the modifier
  # forms and the ternary, whose statements cannot be cut out.
  def modifier?(node)
    closing = CLOSINGS[node.class]
    !closing.nil? && node.public_send(closing).nil?
  end

  def descend(node)
    node.compact_child_nodes.flat_map do |child|
      self.class.opaque?(node, child) ? [child] : [child, *descend(child)]
    end
  end
end
