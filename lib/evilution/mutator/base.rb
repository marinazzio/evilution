# frozen_string_literal: true

require "prism"

require_relative "../mutator"

class Evilution::Mutator::Base < Prism::Visitor
  attr_reader :mutations

  def initialize
    @mutations = []
    @subject = nil
    @file_source = nil
  end

  def call(subject)
    @subject = subject
    @file_source = File.read(subject.file_path)
    @mutations = []
    visit(subject.node)
    @mutations
  end

  private

  def add_mutation(offset:, length:, replacement:, node:)
    mutated_source = Evilution::AST::SourceSurgeon.apply(
      @file_source,
      offset: offset,
      length: length,
      replacement: replacement
    )

    @mutations << Evilution::Mutation.new(
      subject: @subject,
      operator_name: self.class.operator_name,
      original_source: @file_source,
      mutated_source: mutated_source,
      file_path: @subject.file_path,
      line: node.location.start_line,
      column: node.location.start_column
    )
  end

  def self.operator_name
    class_name = name || "anonymous"
    class_name.split("::").last
              .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .downcase
  end
end
