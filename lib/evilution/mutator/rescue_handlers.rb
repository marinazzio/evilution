# frozen_string_literal: true

require "prism"

require_relative "../mutator"
require_relative "../ast/local_reads"

# The rescue clauses of a `begin` (or of a method or block body with a rescue),
# and the rule for which of their handlers can run outside the rescue.
#
# Operators that move a handler — promoting it over the body, or running it
# after the body as well — share the rule: a handler that reads the rescued
# exception (its `=> e` variable or `$!` / `$@`), re-raises it with a bare
# `raise` / `fail`, or retries only makes sense inside the rescue, and moved
# out it would fail for that reason alone.
class Evilution::Mutator::RescueHandlers
  EXCEPTION_GLOBALS = %i[$! $@].freeze
  RERAISING_METHODS = %i[raise fail].freeze

  attr_reader :clauses

  def initialize(begin_node)
    @clauses = []
    clause = begin_node.rescue_clause
    while clause
      @clauses << clause
      clause = clause.subsequent
    end
  end

  # Whether a handler can run outside its rescue. A missing handler (an empty
  # rescue clause) can.
  def self.movable?(handler, reference)
    return true if handler.nil?

    !reads_exception?(handler, reference) && !rescue_only?(handler)
  end

  # Binding the exception to anything but a local (`=> @error`) leaves it set
  # for code after the rescue, which the handler alone cannot speak for, so
  # such a handler counts as reading it. An underscore name announces a binding
  # that is not read.
  def self.reads_exception?(handler, reference)
    return true if nodes_in(handler).any? { |node| exception_global?(node) }
    return false if reference.nil?
    return true unless reference.is_a?(Prism::LocalVariableTargetNode)

    name = reference.name.to_s
    !name.start_with?("_") && Evilution::AST::LocalReads.new.call(handler, name)
  end

  def self.exception_global?(node)
    node.is_a?(Prism::GlobalVariableReadNode) && EXCEPTION_GLOBALS.include?(node.name)
  end

  def self.rescue_only?(handler)
    nodes_in(handler).any? do |node|
      node.is_a?(Prism::RetryNode) ||
        (node.is_a?(Prism::CallNode) && node.receiver.nil? && RERAISING_METHODS.include?(node.name) &&
          node.arguments.nil?)
    end
  end

  def self.nodes_in(node)
    [node, *node.compact_child_nodes.flat_map { |child| nodes_in(child) }]
  end

  private_class_method :reads_exception?, :exception_global?, :rescue_only?, :nodes_in
end
