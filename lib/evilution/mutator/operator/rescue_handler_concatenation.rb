# frozen_string_literal: true

require_relative "../operator"
require_relative "../rescue_handlers"

# Run a rescue handler after the code it protects as well, keeping the rescue:
#
#   begin                  begin
#     fetch(id)              fetch(id)
#   rescue NotFound    ->    rollback
#     rollback             rescue NotFound
#   end                      rollback
#                          end
#
# The failure path is untouched; only a successful run changes, now also
# doing what the handler does. A survivor means the handler is harmless when
# nothing failed — the tests never show it is meant for the failure only.
# Dropping the rescue as well would repeat RescueRemoval and hide this signal
# behind any test of the failure path.
#
# With several rescue clauses each handler is used in its own mutant. An empty
# handler adds nothing and is skipped, as is one that only produces a value
# (`nil`, a literal, a variable, a bare `next`): run after the body it changes
# nothing but the return value, which RescueHandlerPromotion already probes.
# Handlers that only work inside the rescue are skipped too (see
# Mutator::RescueHandlers). A rescue modifier sits in value position, where a
# statement sequence does not fit, and is left alone.
class Evilution::Mutator::Operator::RescueHandlerConcatenation < Evilution::Mutator::Base
  VALUE_TYPES = [
    Prism::NilNode, Prism::TrueNode, Prism::FalseNode, Prism::IntegerNode, Prism::FloatNode,
    Prism::StringNode, Prism::SymbolNode, Prism::SelfNode, Prism::ConstantReadNode,
    Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode
  ].freeze

  def visit_begin_node(node)
    append_handlers(node) if node.rescue_clause && node.statements
    super
  end

  private

  def append_handlers(node)
    body_end = node.statements.location.end_offset
    separator = Evilution::Mutator::RescueHandlers.continuation(@file_source, node.statements)

    Evilution::Mutator::RescueHandlers.new(node).clauses.each do |clause|
      handler = clause.statements
      next if handler.nil? || value_only?(handler)
      next unless Evilution::Mutator::RescueHandlers.movable?(handler, clause.reference)

      add_mutation(offset: body_end, length: 0, replacement: "#{separator}#{handler.slice}", node: clause)
    end
  end

  def value_only?(handler)
    handler.body.all? { |statement| value?(statement) }
  end

  # A method call may act, so only literals, plain reads and a bare `next` /
  # `return` count.
  def value?(statement)
    case statement
    when *VALUE_TYPES then true
    when Prism::ArrayNode, Prism::HashNode then statement.elements.empty?
    when Prism::NextNode, Prism::ReturnNode then statement.arguments.nil?
    else false
    end
  end
end
