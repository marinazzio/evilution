# frozen_string_literal: true

require "prism"
require_relative "../ast"
require_relative "literal_callable"

# The guards and callbacks of an AASM state machine that are written out as
# literal callables:
#
#   aasm do
#     state :paid, before_exit: -> { ... }
#     event :ship, guard: -> { ... } do
#       before { ... }
#       transitions from: :paid, to: :shipped, guard: -> { ... }
#     end
#   end
#
# Each belongs to the `event` or `state` declaration it is written in. AASM
# keeps what a declaration holds by value, so running that one declaration
# again replaces it, and a mutated body takes effect. The machine's own
# callbacks (`after_all_transitions`) accumulate instead, and are left out.
#
# Only a receiver-less `aasm` call with a block, written directly in a class
# body, counts: that is the call the mutated file re-runs.
module Evilution::AST::AasmDeclaration
  # body: the node holding the callable's body. declaration: its `event` or
  # `state` call. method_name: the instance method that declaration defines.
  Callable = Data.define(:body, :declaration, :method_name)

  DECLARATIONS = %i[event state].freeze
  EVENT_CALLBACKS = %i[
    before before_transaction before_success success after after_transaction after_commit error ensure
  ].freeze
  private_constant :DECLARATIONS, :EVENT_CALLBACKS

  # The callables of every machine among a class body's direct statements.
  def self.in_body(body)
    statements_of(body).flat_map { |node| machine_callables(node) }
  end

  # The block of an `aasm` call, or nil when node is not one.
  def self.machine_block(node)
    return nil unless node.is_a?(Prism::CallNode) && node.name == :aasm && node.receiver.nil?

    node.block if node.block.is_a?(Prism::BlockNode)
  end

  # The name specs call for whatever sits on a line of a machine: the event,
  # or the first state, declared there. nil outside every declaration.
  def self.token_at(machine, line)
    declaration = declarations_of(machine).find do |node|
      line.between?(node.location.start_line, node.location.end_line)
    end
    declaration && declared_name(declaration)
  end

  def self.machine_callables(machine)
    declarations_of(machine).flat_map do |declaration|
      bodies_of(declaration).map do |body|
        Callable.new(body: body, declaration: declaration, method_name: method_name(declaration))
      end
    end
  end

  def self.declarations_of(machine)
    block = machine_block(machine)
    return [] unless block

    statements_of(block.body).select { |node| declaration?(node) }
  end

  def self.declaration?(node)
    bare_call?(node) && DECLARATIONS.include?(node.name) && arguments_of(node).first.is_a?(Prism::SymbolNode)
  end

  def self.declared_name(declaration)
    arguments_of(declaration).first.unescaped
  end

  # `event :ship` defines `ship`; `state :paid` defines `paid?`.
  def self.method_name(declaration)
    declaration.name == :event ? declared_name(declaration) : "#{declared_name(declaration)}?"
  end

  def self.bodies_of(declaration)
    keyword_bodies(declaration) + (declaration.name == :event ? event_block_bodies(declaration) : [])
  end

  # What an event's block holds: its transitions, with keyword callables of
  # their own, and callbacks given as blocks (`before { }`).
  def self.event_block_bodies(event)
    return [] unless event.block.is_a?(Prism::BlockNode)

    statements_of(event.block.body).select { |node| bare_call?(node) }.flat_map do |node|
      if node.name == :transitions then keyword_bodies(node)
      elsif callback_block?(node) then [node.block]
      else []
      end
    end
  end

  def self.callback_block?(node)
    EVENT_CALLBACKS.include?(node.name) && node.arguments.nil? && node.block.is_a?(Prism::BlockNode)
  end

  # `guard: -> { }` and `guards: [-> { }, :named]` alike.
  def self.keyword_bodies(call)
    keywords = arguments_of(call).last
    return [] unless keywords.is_a?(Prism::KeywordHashNode)

    keywords.elements.grep(Prism::AssocNode).flat_map do |pair|
      values = pair.value.is_a?(Prism::ArrayNode) ? pair.value.elements : [pair.value]
      values.filter_map { |value| Evilution::AST::LiteralCallable.body_of(value) }
    end
  end

  def self.bare_call?(node)
    node.is_a?(Prism::CallNode) && node.receiver.nil?
  end

  def self.arguments_of(call)
    call.arguments ? call.arguments.arguments : []
  end

  def self.statements_of(body)
    body = body.statements if body.is_a?(Prism::BeginNode)
    body.is_a?(Prism::StatementsNode) ? body.body : []
  end

  private_class_method :machine_callables, :declarations_of, :declaration?, :declared_name, :method_name,
                       :bodies_of, :event_block_bodies, :callback_block?, :keyword_bodies, :bare_call?,
                       :arguments_of, :statements_of
end
