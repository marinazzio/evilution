# frozen_string_literal: true

require "prism"

require_relative "../operator"

class Evilution::Mutator::Operator::SuperclassRemoval < Evilution::Mutator::Base
  def call(subject, filter: nil)
    @subject = subject
    @file_source = File.read(subject.file_path)
    @mutations = []
    @filter = filter

    tree = self.class.parsed_tree_for(subject.file_path, @file_source)
    enclosing = find_enclosing_class(tree, subject.line_number)
    return @mutations unless enclosing
    return @mutations unless enclosing.superclass

    first_method_line = find_first_method_line(enclosing)
    return @mutations unless first_method_line == subject.line_number

    name_end = enclosing.constant_path.location.start_offset + enclosing.constant_path.location.length
    superclass_end = enclosing.superclass.location.start_offset + enclosing.superclass.location.length

    add_mutation(
      offset: name_end,
      length: superclass_end - name_end,
      replacement: "",
      node: enclosing
    )

    @mutations
  end

  private

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
