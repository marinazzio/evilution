# frozen_string_literal: true

require "prism"

require_relative "../operator"
require_relative "../../ast/class_body"

# Drop the superclass from a class definition: `class Admin < User` becomes
# `class Admin`.
#
# The definition line belongs to no method, so the mutant is attributed to
# the method anchoring the class body (see Evilution::AST::ClassBody).
class Evilution::Mutator::Operator::SuperclassRemoval < Evilution::Mutator::Base
  def call(subject, filter: nil)
    @subject = subject
    @file_source = File.read(subject.file_path)
    @mutations = []
    @filter = filter

    classes_with_superclass_for(subject).each do |class_node|
      offset, length = superclass_range(class_node)
      add_mutation(offset: offset, length: length, replacement: "", node: class_node)
    end

    @mutations
  end

  private

  def classes_with_superclass_for(subject)
    tree = self.class.parsed_tree_for(subject.file_path, @file_source)

    Evilution::AST::ClassBody.anchored_at(tree, subject.line_number).map(&:node).select do |scope|
      scope.is_a?(Prism::ClassNode) && scope.superclass
    end
  end

  def superclass_range(class_node)
    name_loc = class_node.constant_path.location
    superclass_loc = class_node.superclass.location
    name_end = name_loc.start_offset + name_loc.length
    superclass_end = superclass_loc.start_offset + superclass_loc.length

    [name_end, superclass_end - name_end]
  end
end
