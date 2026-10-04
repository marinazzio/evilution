# frozen_string_literal: true

require_relative "../operator"

# Swap two adjacent commands: `charge(card); send_receipt(user)` becomes
# `send_receipt(user); charge(card)`.
#
# A survivor means no example depends on the order the two side effects
# happen in. Most pairs of statements could swap without anyone noticing, so
# only pairs that are likely to matter are touched:
#
# - both statements are commands: they call a method, append, write an index,
#   yield or call super. Assigning a local or instance variable stores a
#   value, and statements without such effects swap freely.
# - neither writes a variable the other reads or writes. Such a pair fails at
#   once when swapped, which tests nothing about order.
# - neither contains control flow (`return`, `break`, `next`, `redo`, `retry`,
#   `raise`, `fail`), which would skip the other statement.
# - the second is not the last statement of its body, which gives the body
#   its value.
# - neither contains a heredoc, whose body sits outside the statement's
#   source range.
# - they are not writes to different literal keys of the same receiver
#   (`opts[:a] = 1; opts[:b] = 2`), which cannot affect each other.
class Evilution::Mutator::Operator::StatementReorder < Evilution::Mutator::Base
  CONTROL_FLOW_TYPES = [
    Prism::ReturnNode, Prism::BreakNode, Prism::NextNode, Prism::RedoNode, Prism::RetryNode
  ].freeze
  RAISING_METHODS = %i[raise fail].freeze

  # Calls that change their receiver without a method name: `a << b`, `a[k] = v`.
  MUTATING_OPERATORS = %i[<< []=].freeze
  METHOD_NAME = /\A[a-zA-Z_]/

  EFFECT_TYPES = [Prism::YieldNode, Prism::SuperNode, Prism::ForwardingSuperNode].freeze

  # Statements that store a value rather than act.
  VALUE_WRITE_TYPES = [
    Prism::LocalVariableWriteNode, Prism::LocalVariableOperatorWriteNode,
    Prism::LocalVariableOrWriteNode, Prism::LocalVariableAndWriteNode,
    Prism::InstanceVariableWriteNode, Prism::InstanceVariableOperatorWriteNode,
    Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableAndWriteNode
  ].freeze

  # Nodes that set a variable, and nodes that read one.
  WRITE_TYPES = [
    *VALUE_WRITE_TYPES, Prism::LocalVariableTargetNode, Prism::InstanceVariableTargetNode,
    Prism::ClassVariableWriteNode, Prism::ClassVariableOperatorWriteNode, Prism::ClassVariableOrWriteNode,
    Prism::ClassVariableAndWriteNode, Prism::ClassVariableTargetNode,
    Prism::GlobalVariableWriteNode, Prism::GlobalVariableOperatorWriteNode, Prism::GlobalVariableOrWriteNode,
    Prism::GlobalVariableAndWriteNode, Prism::GlobalVariableTargetNode
  ].freeze
  LITERAL_KEY_TYPES = [Prism::SymbolNode, Prism::StringNode, Prism::IntegerNode].freeze

  READ_TYPES = [
    Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode,
    Prism::ClassVariableReadNode, Prism::GlobalVariableReadNode
  ].freeze

  def visit_statements_node(node)
    statements = node.body
    # The last statement stays put, so pairs end one before it.
    statements[0...-1].each_cons(2) do |first, second|
      emit_swap(first, second) if swappable?(first, second)
    end
    super
  end

  private

  def swappable?(first, second)
    [first, second].all? { |statement| command?(statement) && !control_flow?(statement) && !heredoc?(statement) } &&
      independent?(first, second) && !distinct_key_writes?(first, second)
  end

  def command?(statement)
    return false if VALUE_WRITE_TYPES.include?(statement.class)

    nodes_in(statement).any? { |node| effect?(node) }
  end

  def effect?(node)
    return true if EFFECT_TYPES.include?(node.class)
    return false unless node.is_a?(Prism::CallNode)

    node.name.to_s.match?(METHOD_NAME) || MUTATING_OPERATORS.include?(node.name)
  end

  def control_flow?(statement)
    nodes_in(statement).any? do |node|
      CONTROL_FLOW_TYPES.include?(node.class) ||
        (node.is_a?(Prism::CallNode) && node.receiver.nil? && RAISING_METHODS.include?(node.name))
    end
  end

  def heredoc?(statement)
    nodes_in(statement).any? do |node|
      node.respond_to?(:heredoc?) && node.heredoc?
    end
  end

  def distinct_key_writes?(first, second)
    writes = [index_write(first), index_write(second)]
    return false if writes.include?(nil)
    return false unless writes.first.receiver.slice == writes.last.receiver.slice

    distinct_literal_keys?(writes.map { |write| write.arguments.arguments.first })
  end

  def distinct_literal_keys?(keys)
    keys.all? { |key| LITERAL_KEY_TYPES.include?(key.class) } && keys.first.slice != keys.last.slice
  end

  # `h[k] = v` on its own or under a modifier condition (`h[k] = v if v`).
  def index_write(statement)
    if statement.is_a?(Prism::IfNode) || statement.is_a?(Prism::UnlessNode)
      body = statement.statements
      statement = body.body.first if body && body.body.length == 1
    end
    statement if statement.is_a?(Prism::CallNode) && statement.name == :[]=
  end

  def independent?(first, second)
    first_writes = names(first, WRITE_TYPES)
    second_writes = names(second, WRITE_TYPES)

    !first_writes.intersect?(names(second, READ_TYPES) | second_writes) &&
      !second_writes.intersect?(names(first, READ_TYPES))
  end

  def names(statement, types)
    nodes_in(statement).filter_map { |node| node.name if types.include?(node.class) }.to_set
  end

  def nodes_in(node)
    [node, *node.compact_child_nodes.flat_map { |child| nodes_in(child) }]
  end

  # Whatever separates the two statements — a line break and indentation, or
  # `; ` — stays between them.
  def emit_swap(first, second)
    start_offset = first.location.start_offset
    end_offset = second.location.end_offset
    separator = byteslice_source(first.location.end_offset, second.location.start_offset - first.location.end_offset)

    add_mutation(
      offset: start_offset,
      length: end_offset - start_offset,
      replacement: "#{second.slice}#{separator}#{first.slice}",
      node: first
    )
  end
end
