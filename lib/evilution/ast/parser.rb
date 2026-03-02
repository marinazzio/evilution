# frozen_string_literal: true

require "prism"

module Evilution
  module AST
    class Parser
      def call(file_path)
        source = File.read(file_path)
        result = Prism.parse(source)
        extract_subjects(result.value, source, file_path)
      end

      private

      def extract_subjects(tree, source, file_path)
        finder = SubjectFinder.new(source, file_path)
        finder.visit(tree)
        finder.subjects
      end
    end

    class SubjectFinder < Prism::Visitor
      attr_reader :subjects

      def initialize(source, file_path)
        @source = source
        @file_path = file_path
        @subjects = []
        @context = []
      end

      def visit_module_node(node)
        @context.push(constant_name(node.constant_path))
        super
        @context.pop
      end

      def visit_class_node(node)
        @context.push(constant_name(node.constant_path))
        super
        @context.pop
      end

      def visit_def_node(node)
        scope = @context.join("::")
        name = if scope.empty?
                 "##{node.name}"
               else
                 "#{scope}##{node.name}"
               end

        loc = node.location
        method_source = @source[loc.start_offset...loc.end_offset]

        @subjects << Subject.new(
          name: name,
          file_path: @file_path,
          line_number: loc.start_line,
          source: method_source,
          node: node
        )

        super
      end

      private

      def constant_name(node)
        if node.respond_to?(:full_name)
          node.full_name
        else
          node.name.to_s
        end
      end
    end
  end
end
