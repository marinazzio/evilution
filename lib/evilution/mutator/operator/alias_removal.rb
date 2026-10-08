# frozen_string_literal: true

require "prism"

require_relative "../operator"
require_relative "../../ast/class_body"

# Drop an alias declaration from a class or module body: `alias length size`
# and `alias_method :count, :size` are removed.
#
# A survivor means no example calls the method by its alias, so the alias is
# a surface the suite never exercises — dead, or reached only where nothing
# asserts.
#
# Declarations sit in the class body, outside every method, where no subject
# reaches them. They are attributed to the method anchoring the enclosing
# body (see Evilution::AST::ClassBody); a top-level alias has no body to be
# attributed to. An `alias_method` call inside a method is left to the
# generic call operators, and global-variable aliases (`alias $new $old`)
# are not method surface.
class Evilution::Mutator::Operator::AliasRemoval < Evilution::Mutator::Base
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
    return true if node.is_a?(Prism::AliasMethodNode)

    node.is_a?(Prism::CallNode) && node.name == :alias_method && node.receiver.nil?
  end
end
