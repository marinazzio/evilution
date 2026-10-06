# frozen_string_literal: true

require "prism"
require_relative "../ast"
require_relative "included_block"

# The lines of a file that hold code no subject covers: statements written in
# a class, module or `class << self` body, or at the top level, outside every
# method -- `scope` lambdas, callback macros, constant lists -- or in a
# concern's `included` block, which is a class body written elsewhere. Mutations are
# generated per subject, so a run aimed at these lines generates none of its
# own, and saying so is the only way a reader can tell "nothing to mutate"
# from "nothing reached".
#
# Visibility keywords without arguments (`private`) carry no behaviour of
# their own and are left out.
module Evilution::AST::UncoveredCode
  SCOPE_NODES = [Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze
  VISIBILITY_KEYWORDS = %i[private protected public module_function].freeze
  private_constant :SCOPE_NODES, :VISIBILITY_KEYWORDS

  # subjects: those parsed from file_path; lines: the Range to keep, or nil
  # for the whole file. Returns the uncovered lines as merged Ranges, in
  # source order.
  def self.call(file_path, subjects, lines:)
    covered = subjects.flat_map { |subject| subject_lines(subject) }.to_set
    uncovered = code_lines(File.read(file_path)).reject { |line| covered.include?(line) }
    uncovered = uncovered.select { |line| lines.cover?(line) } if lines
    merge(uncovered.uniq)
  end

  def self.code_lines(source)
    statements(Prism.parse(source).value.statements).flat_map { |node| node_lines(node) }
  end

  def self.statements(body)
    nodes = case body
            when Prism::StatementsNode then body.body
            when Prism::BeginNode then body.statements ? body.statements.body : []
            else []
            end
    nodes.flat_map { |node| expand(node) }
  end

  def self.expand(node)
    return statements(node.body) if SCOPE_NODES.any? { |type| node.is_a?(type) }

    included = Evilution::AST::IncludedBlock.of(node)
    return statements(included.body) if included
    return [] if bare_visibility?(node)

    [node]
  end

  def self.bare_visibility?(node)
    node.is_a?(Prism::CallNode) && node.receiver.nil? && node.arguments.nil? &&
      VISIBILITY_KEYWORDS.include?(node.name)
  end

  def self.node_lines(node)
    (node.start_line..node.end_line).to_a
  end

  def self.subject_lines(subject)
    (subject.line_number..(subject.line_number + subject.source.count("\n"))).to_a
  end

  def self.merge(lines)
    lines.slice_when { |a, b| b != a + 1 }.map { |run| run.first..run.last }
  end

  private_class_method :code_lines, :statements, :expand, :bare_visibility?, :node_lines, :subject_lines, :merge
end
