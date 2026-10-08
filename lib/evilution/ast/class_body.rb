# frozen_string_literal: true

require "prism"
require_relative "../ast"

# The body of a class, module or `class << self`: the code written outside
# every method, where no method subject reaches it.
#
# Operators that mutate such code attribute their mutants to one method, so
# each mutant has exactly one subject. That method is the scope's anchor: the
# first method written in the scope, in source order. Blocks of the body
# (`included do ... end`) are searched, nested scopes are not: their methods
# anchor the inner scope. A scope with no method of its own borrows the anchor
# of the first singleton class in its body that has one, so a class whose
# methods all sit in `class << self` is still reached.
class Evilution::AST::ClassBody
  SCOPES = [Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze
  # Nodes whose children belong to something else: a method, or another scope.
  OPAQUE = [Prism::DefNode, *SCOPES].freeze

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
    scopes_in(tree).map { |scope| new(scope) }.select { |body| body.anchor_line == line }
  end

  def self.scopes_in(node)
    node.compact_child_nodes.flat_map do |child|
      nested = scopes_in(child)
      SCOPES.include?(child.class) ? [child, *nested] : nested
    end
  end

  private_class_method :scopes_in

  def initialize(node)
    @node = node
  end

  def anchor_line
    first_method = contents.find { |child| child.is_a?(Prism::DefNode) }
    return first_method.location.start_line if first_method

    singleton_classes = contents.grep(Prism::SingletonClassNode)
    singleton_classes.filter_map { |scope| self.class.new(scope).anchor_line }.first
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

  # Every node written in the scope, in source order, down to the methods and
  # nested scopes, which are listed but not entered. The scope's own header
  # (its name, its superclass expression) is not part of the body.
  def contents
    @contents ||= @node.body ? descend(@node.body) : []
  end

  def statements_in(node, removable:)
    node.compact_child_nodes.flat_map do |child|
      next [] if OPAQUE.include?(child.class)

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
      OPAQUE.include?(child.class) ? [child] : [child, *descend(child)]
    end
  end
end
