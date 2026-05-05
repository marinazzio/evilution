# frozen_string_literal: true

require "prism"

require_relative "../operator"

class Evilution::Mutator::Operator::SuperclassRemoval < Evilution::Mutator::Base
  def call(subject, filter: nil)
    @subject = subject
    @file_source = File.read(subject.file_path)
    @mutations = []
    @filter = filter

    enclosing = find_target_class(subject)
    return @mutations unless enclosing

    offset, length = superclass_range(enclosing)
    add_mutation(offset: offset, length: length, replacement: "", node: enclosing)

    @mutations
  end

  private

  def find_target_class(subject)
    tree = self.class.parsed_tree_for(subject.file_path, @file_source)
    enclosing = find_enclosing_class(tree, subject.line_number)
    return nil unless enclosing && enclosing.superclass
    return nil unless find_first_method_line(enclosing) == subject.line_number

    enclosing
  end

  def superclass_range(class_node)
    name_loc = class_node.constant_path.location
    superclass_loc = class_node.superclass.location
    name_end = name_loc.start_offset + name_loc.length
    superclass_end = superclass_loc.start_offset + superclass_loc.length

    [name_end, superclass_end - name_end]
  end

  def find_enclosing_class(tree, target_line)
    finder = ClassFinder.new(target_line)
    finder.visit(tree)
    finder.result
  end

  def find_first_method_line(class_node)
    return nil unless class_node.body

    class_node.body.body.each do |node|
      return node.location.start_line if node.is_a?(Prism::DefNode)
    end
    nil
  end

  # Visitor to find the ClassNode enclosing a given line number.
  class ClassFinder < Prism::Visitor
    attr_reader :result

    def initialize(target_line)
      @target_line = target_line
      @result = nil
    end

    def visit_class_node(node)
      @result = node if @target_line.between?(node.location.start_line, node.location.end_line)
      super
    end
  end
end
