# frozen_string_literal: true

require "prism"

require_relative "../operator"

class Evilution::Mutator::Operator::MixinRemoval < Evilution::Mutator::Base
  MIXIN_METHODS = %i[include extend prepend].freeze

  def call(subject)
    @subject = subject
    @file_source = File.read(subject.file_path)
    @mutations = []

    tree = self.class.parsed_tree_for(subject.file_path, @file_source)
    enclosing = find_enclosing_scope(tree, subject.line_number)
    return @mutations unless enclosing

    first_method_line = find_first_method_line(enclosing)
    return @mutations unless first_method_line == subject.line_number

    find_mixin_calls(enclosing).each do |call_node|
      add_mutation(
        offset: call_node.location.start_offset,
        length: call_node.location.length,
        replacement: "",
        node: call_node
      )
    end

    @mutations
  end

  private

  def find_enclosing_scope(tree, target_line)
    finder = ScopeFinder.new(target_line)
    finder.visit(tree)
    finder.result
  end

  def find_first_method_line(scope_node)
    return nil unless scope_node.body

    scope_node.body.body.each do |node|
      return node.location.start_line if node.is_a?(Prism::DefNode)
    end
    nil
  end

  def find_mixin_calls(scope_node)
    return [] unless scope_node.body

    scope_node.body.body.select do |node|
      node.is_a?(Prism::CallNode) &&
        MIXIN_METHODS.include?(node.name) &&
        node.receiver.nil?
    end
  end

  # Visitor to find the ClassNode or ModuleNode enclosing a given line number.
  class ScopeFinder < Prism::Visitor
    attr_reader :result

    def initialize(target_line)
      @target_line = target_line
      @result = nil
    end

    def visit_class_node(node)
      @result = node if @target_line.between?(node.location.start_line, node.location.end_line)
      super
    end

    def visit_module_node(node)
      @result = node if @target_line.between?(node.location.start_line, node.location.end_line)
      super
    end
  end
end
