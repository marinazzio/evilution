# frozen_string_literal: true

require "prism"

require_relative "../mutator"
require_relative "primitives"
require_relative "constant_value_subjects"
require_relative "receiver_positions"
require_relative "../integration/loading/body_call_neutralizer"
require_relative "../ast/heredoc_span"
require_relative "../ast/parse_cache"
require_relative "../ast/source_surgeon"
require_relative "../ast/def_region"
require_relative "../ast/class_body"
require_relative "line_range_filter"
require_relative "restore_source_cache"
require_relative "load_sources"

class Evilution::Mutator::Base < Prism::Visitor
  include Evilution::Mutator::Primitives

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

  # line_ranges: file path => the line range a run asked for in that file;
  # only mutations that change a line of it are built.
  def initialize(line_ranges: {}, **_options)
    @mutations = []
    @subject = nil
    @file_source = nil
    @line_range_filter = Evilution::Mutator::LineRangeFilter.new(line_ranges)
    @body_call_neutralizer = Evilution::Integration::Loading::BodyCallNeutralizer.new
  end

  # file_source: the subject's file as read for every operator of the run;
  # read here when not handed over.
  def call(subject, filter: nil, file_source: nil)
    prepare(subject, filter: filter, file_source: file_source)
    visit(subject.node)
    @mutations
  end

  private

  def prepare(subject, filter:, file_source:)
    @subject = subject
    @file_source = file_source || File.read(subject.file_path)
    @mutations = []
    @filter = filter
    @def_region = nil
    @load_sources = nil
  end

  # `skip_unparseable` makes the mutation vanish rather than be recorded when
  # the surgery does not parse. Off by default: the point operators rely on
  # unparseable bytes reaching the reporter as their own bucket. The shared
  # primitives opt in, since a nil-ification or promotion that does not parse
  # carries no signal.
  def add_mutation(offset:, length:, replacement:, node:, skip_unparseable: false)
    length = heredoc_safe_length(node, offset, length, replacement)
    return unless length

    # Checked before any surgery: a mutation outside the requested lines is
    # never run, so building it would be wasted work.
    lines = changed_lines(node, offset, length)
    return unless @line_range_filter.cover?(@subject.file_path, lines)

    mutated = Evilution::AST::SourceSurgeon.splice(@file_source, offset: offset, length: length, replacement: replacement)
    surgery = checked_unless_ignored(node, mutated, { offset: offset, length: length, replacement: replacement },
                                     skip_unparseable)
    return unless surgery

    slices = slice_affected_lines(
      mutated_source: surgery.source,
      offset: offset,
      length: length,
      replacement_bytesize: replacement.bytesize
    )

    mutation = build_mutation_record(node, surgery, slices, offset, lines)
    @mutations << mutation
    mutation
  end

  # The length the edit takes once a heredoc it opens is swept with it, or nil
  # when it cannot be made.
  #
  # When the byte range opens a heredoc but stops at its inline anchor,
  # extend it to cover the body+terminator. Without this every operator
  # whose edit straddles a `<<~MARKER` anchor (argument_removal,
  # argument_nil_substitution, method_call_removal, statement_deletion,
  # method_body_replacement, block_removal, conditional_branch,
  # string_interpolation, ...) emits an orphan-heredoc unparseable.
  #
  # If the replacement re-references a heredoc anchor (e.g. argument_removal
  # rebuilding the args list with a kept `<<~MSG` arg), we cannot safely
  # extend the range — doing so would strip the kept heredoc's body without
  # putting it back. Skip the mutation rather than emit unparseable bytes.
  # When the replacement is heredoc-free (nil, "", a literal, or a non-
  # heredoc kept arg), extension cleanly sweeps the orphaned body+terminator.
  def heredoc_safe_length(node, offset, length, replacement)
    extended = Evilution::AST::HeredocSpan.extend_length(node: node, offset: offset, length: length)
    extended unless extended > length && replacement.match?(HEREDOC_ANCHOR_PATTERN)
  end

  # The checked mutation, or nil when it is ignored or vanishes for not
  # parsing. The filter is asked only of a mutation that would be built
  # otherwise -- in the requested lines, its heredoc intact, parseable when it
  # has to be -- so the ignored ones counted are ones the run would have made.
  # The check, a parse, is left until the filter has passed the mutation
  # unless the mutation hangs on it.
  def checked_unless_ignored(node, mutated, edit, skip_unparseable)
    surgery = check(mutated, edit) if skip_unparseable
    return if skip_unparseable && surgery.unparseable?
    return if ignored?(node, mutated)

    surgery || check(mutated, edit)
  end

  # A mutation inside the subject's method is checked by parsing the method
  # alone when that settles it (see AST::DefRegion); the whole file is
  # parsed otherwise.
  def check(mutated, edit)
    Evilution::AST::SourceSurgeon.check(mutated) { def_region.parse(**edit) }
  end

  def def_region
    @def_region ||= Evilution::AST::DefRegion.new(@file_source, @subject.node)
  end

  def ignored?(node, mutated_source)
    return false unless @filter

    @filter.skip?(node, file_path: @subject.file_path, source: @file_source, mutated_source: mutated_source)
  end

  def build_mutation_record(node, surgery, slices, offset, changed_lines)
    Evilution::Mutation.new(
      subject: @subject,
      operator_name: self.class.operator_name,
      sources: Evilution::Mutation::Sources.new(original: @file_source, mutated: surgery.source),
      slice: Evilution::Mutation::Slice.new(original: slices.original, mutated: slices.mutated),
      location: Evilution::Mutation::Location.new(
        file_path: @subject.file_path,
        line: node.location.start_line,
        column: node.location.start_column,
        lines: changed_lines
      ),
      parse_status: surgery.status,
      eval_source: build_eval_source(surgery, offset),
      restore_source: build_restore_source(offset)
    )
  end

  # The original lines the replaced bytes sit on; an insertion changes the
  # line it is made on. Counted from the node rather than the top of the file,
  # so only the bytes between the node and the edit are scanned.
  def changed_lines(node, offset, length)
    first = line_at(offset, node)
    last = first + line_breaks_in(offset, [length - 1, 0].max)
    first..last
  end

  # Prism knows the node's line; the edit's is found by counting the line
  # breaks between the two, forwards or backwards.
  def line_at(offset, node)
    from, to = [offset, node.start_offset].minmax
    node.start_line + ((offset <=> node.start_offset) * line_breaks_in(from, to - from))
  end

  # Counted on the raw bytes: a byte range can start or end inside a multibyte
  # character, and counting such a slice as UTF-8 raises.
  def line_breaks_in(offset, length)
    @file_source.byteslice(offset, length).b.count("\n")
  end

  # The source a worker evaluates for the mutation, and the one it evaluates
  # afterwards to put the file back (see LoadSources).
  def build_eval_source(surgery, offset)
    load_sources.eval_source(surgery, offset)
  end

  def build_restore_source(offset)
    load_sources.restore_source(offset)
  end

  def load_sources
    @load_sources ||= Evilution::Mutator::LoadSources.new(@subject, @file_source, @body_call_neutralizer)
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

  # The kinds of Subject the operator mutates. Operators work on method
  # bodies, and on the bodies of callables handed to a scope, aasm or
  # callback declaration, which run as part of the class's behaviour; one that also has
  # something to say about a constant subject (a definition outside any
  # method) adds :constant.
  def self.subject_kinds
    %i[method scope aasm callback]
  end

  def self.parsed_tree_for(file_path, file_source)
    Evilution::AST::ParseCache.tree_for(file_path, file_source)
  end

  def self.clear_parse_cache!
    Evilution::AST::ParseCache.clear!
    Evilution::AST::ClassBody.clear!
    Evilution::Mutator::RestoreSourceCache.clear!
  end
end
