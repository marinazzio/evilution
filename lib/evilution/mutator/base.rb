# frozen_string_literal: true

require "prism"

require_relative "../mutator"

class Evilution::Mutator::Base < Prism::Visitor
  attr_reader :mutations

  def initialize(**_options)
    @mutations = []
    @subject = nil
    @file_source = nil
  end

  def call(subject, filter: nil)
    @subject = subject
    @file_source = File.read(subject.file_path)
    @mutations = []
    @filter = filter
    visit(subject.node)
    @mutations
  end

  private

  def add_mutation(offset:, length:, replacement:, node:)
    return if @filter && @filter.skip?(node)

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

  def byteslice_source(offset, length)
    @file_source.byteslice(offset, length).force_encoding(@file_source.encoding)
  end

  def self.operator_name
    class_name = name || "anonymous"
    class_name.split("::").last
              .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .downcase
  end

  @parse_cache = {}

  def self.parsed_tree_for(file_path, file_source)
    cache = Evilution::Mutator::Base.instance_variable_get(:@parse_cache)
    entry = cache[file_path]
    return entry[:tree] if entry && entry[:source_hash] == file_source.hash

    tree = Prism.parse(file_source).value
    cache[file_path] = { source_hash: file_source.hash, tree: tree }
    tree
  end

  def self.clear_parse_cache!
    Evilution::Mutator::Base.instance_variable_set(:@parse_cache, {})
  end
end
