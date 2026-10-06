# frozen_string_literal: true

require "prism"
require_relative "../ast"
require_relative "literal_callable"

# The callables written out in a callback or validation declaration of a
# class body:
#
#   validate :credit_limit, if: -> { paid? && total.positive? }
#   validates :title, presence: true, unless: [-> { draft? }, :imported?]
#   before_save { self.slug = title.parameterize }
#   after_commit -> { notify }, on: :create
#
# That is the condition given to `if:` / `unless:`, and the callback itself
# when it is a block or a lambda. A condition or callback named by a symbol
# is a method, and a subject of its own already.
#
# Declarations are recognised by name -- `validate`, `validates`,
# `validates_*`, `before_*`, `after_*`, `around_*` -- and only receiver-less,
# directly in a class body: that is the call the mutated file re-runs.
module Evilution::AST::CallbackDeclaration
  # body: the node holding the callable's body. declaration: the call it is
  # written in. label: how the declaration reads, for naming the subject.
  Callable = Data.define(:body, :declaration, :label)

  NAME = /\A(?:validate|validates|validates_\w+|(?:before|after|around)_\w+)\z/
  CONDITIONS = %w[if unless].freeze
  private_constant :NAME, :CONDITIONS

  # The callables of every callback declaration among a class body's direct
  # statements.
  def self.in_body(body)
    statements = body.is_a?(Prism::BeginNode) ? body.statements : body
    return [] unless statements.is_a?(Prism::StatementsNode)

    statements.body.select { |node| match?(node) }.flat_map { |declaration| callables(declaration) }
  end

  # Whether node is a callback declaration that can be run again on its own.
  # One holding a heredoc cannot be wrapped on its own lines, and is left out.
  def self.match?(node)
    node.is_a?(Prism::CallNode) && node.receiver.nil? && NAME.match?(node.name.to_s) && !heredoc?(node)
  end

  def self.callables(declaration)
    label = label_of(declaration)
    bodies_of(declaration).map { |body| Callable.new(body: body, declaration: declaration, label: label) }
  end

  # `validate :credit_limit, if: ...` reads as `validate(:credit_limit)`; a
  # declaration naming nothing, as its own name.
  def self.label_of(declaration)
    named = arguments_of(declaration).find { |argument| argument.is_a?(Prism::SymbolNode) }
    named ? "#{declaration.name}(:#{named.unescaped})" : declaration.name.to_s
  end

  def self.bodies_of(declaration)
    arguments = arguments_of(declaration)
    bodies = arguments.filter_map { |argument| Evilution::AST::LiteralCallable.body_of(argument) }
    bodies.concat(condition_bodies(arguments.last))
    bodies << declaration.block if declaration.block.is_a?(Prism::BlockNode)
    bodies
  end

  # `if: -> { }` and `unless: [-> { }, :named]` alike.
  def self.condition_bodies(keywords)
    return [] unless keywords.is_a?(Prism::KeywordHashNode)

    keywords.elements.select { |pair| condition?(pair) }.flat_map do |pair|
      values = pair.value.is_a?(Prism::ArrayNode) ? pair.value.elements : [pair.value]
      values.filter_map { |value| Evilution::AST::LiteralCallable.body_of(value) }
    end
  end

  def self.condition?(pair)
    pair.is_a?(Prism::AssocNode) && pair.key.is_a?(Prism::SymbolNode) && CONDITIONS.include?(pair.key.unescaped)
  end

  def self.arguments_of(call)
    call.arguments ? call.arguments.arguments : []
  end

  def self.heredoc?(node)
    return true if node.respond_to?(:heredoc?) && node.heredoc?

    node.compact_child_nodes.any? { |child| heredoc?(child) }
  end

  private_class_method :callables, :label_of, :bodies_of, :condition_bodies, :condition?, :arguments_of, :heredoc?
end
