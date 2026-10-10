# frozen_string_literal: true

require "prism"

require_relative "../operator"
require_relative "../../ast/class_body"

# Drop a visibility declaration from a class or module body: `private`,
# `protected` and `module_function`, bare or naming methods. A definition the
# declaration wraps is kept: `private def a; end` becomes `def a; end`.
#
# A survivor means no example checks what the declaration decides: that a
# private method cannot be called from outside, or that a module function
# can.
#
# Declarations sit in the class body, outside every method, where no subject
# reaches them. They are attributed to the method anchoring the enclosing
# body (see Evilution::AST::ClassBody); a top-level declaration has no body
# to be attributed to. A call inside a method, or one sent to another
# receiver, is not a declaration.
class Evilution::Mutator::Operator::VisibilityRemoval < Evilution::Mutator::Base
  DECLARATIONS = %i[private protected module_function].freeze

  # What a declaration can wrap and has to leave behind: a method definition,
  # or a call (`private attr_reader :name`, `private helper_names`). The call
  # runs with or without the declaration, so it stays.
  WRAPPED = [Prism::DefNode, Prism::CallNode].freeze

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
    replacement = replacement_for(declaration.arguments ? declaration.arguments.arguments : [])
    return if replacement.nil?

    add_mutation(
      offset: declaration.location.start_offset,
      length: declaration.location.length,
      replacement: replacement,
      node: declaration
    )
  end

  # What is left of the declaration: nothing when it only names methods, the
  # definition when it wraps one. A definition among several arguments
  # (`private attr_reader(:a), :b`) cannot be left behind on its own, so that
  # declaration is not mutated.
  def replacement_for(arguments)
    return "" if arguments.none? { |argument| WRAPPED.include?(argument.class) }

    arguments.first.slice if arguments.one?
  end

  def declarations_for(subject)
    tree = self.class.parsed_tree_for(subject.file_path, @file_source)

    Evilution::AST::ClassBody.anchored_at(tree, subject.line_number).flat_map do |body|
      body.declarations { |node| declaration?(node) }
    end
  end

  def declaration?(node)
    node.is_a?(Prism::CallNode) && node.receiver.nil? && DECLARATIONS.include?(node.name)
  end
end
