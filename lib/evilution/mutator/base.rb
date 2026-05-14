# frozen_string_literal: true

require "prism"

require_relative "../mutator"
require_relative "../integration/loading/body_call_neutralizer"
require_relative "../ast/heredoc_span"

class Evilution::Mutator::Base < Prism::Visitor
  AffectedSlices = Data.define(:original, :mutated)
  private_constant :AffectedSlices

  # Match a heredoc anchor `<<MARKER` / `<<-MARKER` / `<<~MARKER` (optionally
  # quoted) when the identifier sits directly against the `<<` (or its
  # `-`/`~`/quote prefix). The space-separated forms `arr << x`, `1 << 2`,
  # `class << self` deliberately do NOT match — `<<` alone is also Ruby's
  # shift / append / singleton-class operator, and skipping mutations that
  # only contain those would lose useful coverage. False positive on the
  # unusual no-space shift `obj<<value` is accepted (over-skip is safer than
  # emitting an unparseable mutation).
  HEREDOC_ANCHOR_PATTERN = /<<[-~]?["'`]?[A-Za-z_]/
  private_constant :HEREDOC_ANCHOR_PATTERN

  attr_reader :mutations

  def initialize(**_options)
    @mutations = []
    @subject = nil
    @file_source = nil
    @body_call_neutralizer = Evilution::Integration::Loading::BodyCallNeutralizer.new
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

    # When the byte range opens a heredoc but stops at its inline anchor,
    # extend it to cover the body+terminator. Without this every operator
    # whose edit straddles a `<<~MARKER` anchor (argument_removal,
    # argument_nil_substitution, method_call_removal, statement_deletion,
    # method_body_replacement, block_removal, conditional_branch,
    # string_interpolation, ...) emits an orphan-heredoc unparseable.
    extended_length = Evilution::AST::HeredocSpan.extend_length(
      node: node, offset: offset, length: length
    )

    # If the replacement re-references a heredoc anchor (e.g. argument_removal
    # rebuilding the args list with a kept `<<~MSG` arg), we cannot safely
    # extend the range — doing so would strip the kept heredoc's body without
    # putting it back. Skip the mutation rather than emit unparseable bytes.
    # When the replacement is heredoc-free (nil, "", a literal, or a non-
    # heredoc kept arg), extension cleanly sweeps the orphaned body+terminator.
    return if extended_length > length && replacement.match?(HEREDOC_ANCHOR_PATTERN)

    length = extended_length

    surgery = Evilution::AST::SourceSurgeon.apply(
      @file_source, offset: offset, length: length, replacement: replacement
    )
    slices = slice_affected_lines(
      mutated_source: surgery.source,
      offset: offset,
      length: length,
      replacement_bytesize: replacement.bytesize
    )

    @mutations << build_mutation_record(node, surgery, slices)
  end

  def build_mutation_record(node, surgery, slices)
    Evilution::Mutation.new(
      subject: @subject,
      operator_name: self.class.operator_name,
      sources: Evilution::Mutation::Sources.new(original: @file_source, mutated: surgery.source),
      slice: Evilution::Mutation::Slice.new(original: slices.original, mutated: slices.mutated),
      location: Evilution::Mutation::Location.new(
        file_path: @subject.file_path,
        line: node.location.start_line,
        column: node.location.start_column
      ),
      parse_status: surgery.status,
      eval_source: build_eval_source(surgery)
    )
  end

  # Pre-compute the worker's eval target so per-iter Prism re-parse cost
  # stays out of the hot path. For parseable mutations we strip class/module
  # body calls that are known to be non-idempotent (registries etc.); for
  # unparseable bytes we fall through so the syntax validator can reject
  # them at apply time. Passing the subject's file path lets the neutralizer
  # skip files the parent never preloaded — those are lazy plugin files whose
  # DSL calls are still needed for the child fork's first-time load.
  def build_eval_source(surgery)
    return surgery.source unless surgery.ok?

    @body_call_neutralizer.call(surgery.source, file_path: @subject.file_path)
  end

  NEWLINE_BYTE = 10
  private_constant :NEWLINE_BYTE

  def slice_affected_lines(mutated_source:, offset:, length:, replacement_bytesize:)
    line_start = line_start_byte(@file_source, offset)
    orig_line_end = line_end_byte(@file_source, [offset + length - 1, line_start].max)
    mut_line_end = line_end_byte(mutated_source, [offset + replacement_bytesize - 1, line_start].max)

    AffectedSlices.new(
      original: @file_source.byteslice(line_start, orig_line_end - line_start),
      mutated: mutated_source.byteslice(line_start, mut_line_end - line_start)
    )
  end

  def line_start_byte(source, offset)
    i = offset - 1
    i -= 1 while i >= 0 && source.getbyte(i) != NEWLINE_BYTE
    i + 1
  end

  def line_end_byte(source, from)
    limit = source.bytesize
    i = from
    i += 1 while i < limit && source.getbyte(i) != NEWLINE_BYTE
    i < limit ? i + 1 : limit
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
