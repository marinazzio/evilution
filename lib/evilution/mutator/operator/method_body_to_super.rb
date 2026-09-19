# frozen_string_literal: true

require "prism"

require_relative "../operator"

# Replace a whole method body with a bare `super`: `def foo; body; end` becomes
# `def foo; super; end`.
#
# A survivor means the override adds nothing the suite asserts over the
# inherited implementation. MethodBodyReplacement emits the same replacement,
# but only for a body that already calls super, so a plain override — the case
# worth probing — is never reached by it.
#
# `super` needs somewhere to go: without one the mutant raises NoMethodError and
# dies on contact, which scores a kill that proves nothing. Emission is
# therefore limited to methods whose enclosing scope supplies a super target:
# an explicit superclass, or a mixin in the right position for that kind of
# method (include/prepend for instance methods, extend for singleton ones).
class Evilution::Mutator::Operator::MethodBodyToSuper < Evilution::Mutator::Base
  INSTANCE_MIXINS = %i[include prepend].freeze
  SINGLETON_MIXINS = %i[extend].freeze

  def visit_def_node(node)
    replace_body_with_super(node)
    super
  end

  private

  def replace_body_with_super(node)
    statements = body_statements(node.body)
    return if statements.nil?
    return if calls_super?(statements)
    return unless super_target?(node)

    location = statements.location

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: "super",
      node: node
    )
  end

  # A method-level rescue/ensure (`def foo; stmts; rescue; ...; end`) makes the
  # body a BeginNode whose location spans the entire `def...end`, keyword and
  # matching `end` included. Replacing that range would delete the method
  # framing, so only the leading statements are replaceable. Returns nil for a
  # rescue/ensure-only body and for an empty method, whose body is nil.
  def body_statements(body)
    return body unless body.is_a?(Prism::BeginNode)

    body.statements
  end

  # MethodBodyReplacement owns bodies that already reach for the parent
  # implementation; emitting here would attribute one mutation to two operators.
  def calls_super?(node)
    return true if node.is_a?(Prism::SuperNode) || node.is_a?(Prism::ForwardingSuperNode)

    node.child_nodes.any? { |child| child && calls_super?(child) }
  end

  # `def self.foo` and a def inside `class << self` both define singleton
  # methods, which inherit through the singleton class: an explicit superclass
  # carries them, `extend` mixes into them, `include`/`prepend` do not.
  def super_target?(def_node)
    scope = enclosing_scope(def_node)
    return false unless scope

    singleton = def_node.receiver || scope[:singleton]
    return true if scope[:node].is_a?(Prism::ClassNode) && scope[:node].superclass

    mixins = singleton ? SINGLETON_MIXINS : INSTANCE_MIXINS
    mixin?(scope[:node], mixins)
  end

  # The innermost class or module containing the def. A `class << self` body is
  # transparent to the search — the mixins that matter live in the class around
  # it — but it marks everything inside as a singleton method.
  def enclosing_scope(def_node)
    tree = self.class.parsed_tree_for(@subject.file_path, @file_source)
    finder = ScopeFinder.new(def_node.location.start_line)
    finder.visit(tree)
    finder.result
  end

  # A scope is only consulted once a def was found inside it, so its body is
  # never nil here. A bare `include` with nothing to mix in parses with a nil
  # arguments node, which is what separates it from a real mixin call.
  def mixin?(scope_node, names)
    scope_node.body.body.any? do |child|
      child.is_a?(Prism::CallNode) && child.receiver.nil? &&
        names.include?(child.name) && child.arguments
    end
  end

  # Visitor that reports the innermost class/module enclosing a line, and
  # whether that line sits inside a `class << self` body.
  class ScopeFinder < Prism::Visitor
    def initialize(target_line)
      @target_line = target_line
      @scope = nil
      @singleton = false
      super()
    end

    # The enclosing scope and the `class << self` flag are collected
    # independently: the class node is visited before the singleton-class body
    # inside it, so a flag read at that point would always be false.
    def result
      return nil unless @scope

      { node: @scope, singleton: @singleton }
    end

    def visit_class_node(node)
      @scope = node if covers?(node)
      super
    end

    def visit_module_node(node)
      @scope = node if covers?(node)
      super
    end

    def visit_singleton_class_node(node)
      @singleton = true if covers?(node)
      super
    end

    private

    def covers?(node)
      @target_line.between?(node.location.start_line, node.location.end_line)
    end
  end
end
