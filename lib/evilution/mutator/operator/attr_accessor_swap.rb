# frozen_string_literal: true

require "prism"

require_relative "../operator"
require_relative "../../ast/class_body"

# Mutate an attribute declaration in a class or module body two ways.
#
# Widening: `attr_reader :name` and `attr_writer :name` become
# `attr_accessor :name`. A survivor means no example checks that the missing
# half is missing: that the attribute cannot be written, or cannot be read.
#
# Removal: an `attr_reader`, `attr_writer` or `attr_accessor` declaration is
# dropped. A survivor means no example uses any of the methods it defines.
#
# Declarations sit in the class body, outside every method, where no subject
# reaches them. They are attributed to the method anchoring the enclosing
# body (see Evilution::AST::ClassBody); a top-level declaration has no body
# to be attributed to. A declaration wrapped in a visibility call
# (`private attr_reader :name`) is left alone: removing it would leave a bare
# `private` behind.
class Evilution::Mutator::Operator::AttrAccessorSwap < Evilution::Mutator::Base
  WIDENED = "attr_accessor"
  NARROW = %i[attr_reader attr_writer].freeze
  DECLARATIONS = [*NARROW, :attr_accessor].freeze

  def call(subject, filter: nil)
    @subject = subject
    @file_source = File.read(subject.file_path)
    @mutations = []
    @filter = filter

    declarations_for(subject).each do |declaration|
      widen(declaration) if NARROW.include?(declaration.name)
      remove(declaration)
    end
    @mutations
  end

  private

  def widen(declaration)
    name = declaration.message_loc
    add_mutation(offset: name.start_offset, length: name.length, replacement: WIDENED, node: declaration)
  end

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

    Evilution::AST::ClassBody.anchored_at(tree, subject.line_number).flat_map do |body|
      body.declarations { |node| declaration?(node) }
    end
  end

  def declaration?(node)
    node.is_a?(Prism::CallNode) && node.receiver.nil? && DECLARATIONS.include?(node.name) && !node.arguments.nil?
  end
end
