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

    original_slice, mutated_slice = slice_affected_lines(
      mutated_source: mutated_source,
      offset: offset,
      length: length,
      replacement_bytesize: replacement.bytesize
    )

    @mutations << Evilution::Mutation.new(
      subject: @subject,
      operator_name: self.class.operator_name,
      original_source: @file_source,
      mutated_source: mutated_source,
      original_slice: original_slice,
      mutated_slice: mutated_slice,
      file_path: @subject.file_path,
      line: node.location.start_line,
      column: node.location.start_column
    )
  end

  def slice_affected_lines(mutated_source:, offset:, length:, replacement_bytesize:)
    original_binary = @file_source.b
    line_start = offset.zero? ? 0 : (original_binary.rindex("\n", offset - 1) || -1) + 1
    orig_end_search = [offset + length - 1, line_start].max
    orig_line_end = original_binary.index("\n", orig_end_search)
    orig_line_end = orig_line_end ? orig_line_end + 1 : original_binary.bytesize

    mutated_binary = mutated_source.b
    mut_end_search = [offset + replacement_bytesize - 1, line_start].max
    mut_line_end = mutated_binary.index("\n", mut_end_search)
    mut_line_end = mut_line_end ? mut_line_end + 1 : mutated_binary.bytesize

    original_slice = original_binary.byteslice(line_start, orig_line_end - line_start)
                                    .force_encoding(@file_source.encoding)
    mutated_slice = mutated_binary.byteslice(line_start, mut_line_end - line_start)
                                  .force_encoding(mutated_source.encoding)
    [original_slice, mutated_slice]
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
