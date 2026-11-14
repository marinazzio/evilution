# frozen_string_literal: true

require "diff/lcs"
require_relative "version"

class Evilution::Mutation
  Sources = Data.define(:original, :mutated)
  Slice = Data.define(:original, :mutated)
  # lines: the lines of the original file the mutation's bytes sit on. A
  # mutation is reported at the line its node starts on, which need not be the
  # first line it changes, and it can change several. Left out, it is taken to
  # change only the line it is reported at.
  Location = Data.define(:file_path, :line, :column, :lines) do
    def initialize(file_path:, line:, column:, lines: line..line)
      super
    end
  end

  # What a mutation holds once its sources are released (see strip_sources!),
  # and when it was built without a slice. Their fields read as nil, so the
  # readers below need no nil check of their own.
  STRIPPED_SOURCES = Sources.new(original: nil, mutated: nil)
  NO_SLICE = Slice.new(original: nil, mutated: nil)
  private_constant :STRIPPED_SOURCES, :NO_SLICE

  # restore_source: the original file, evaluated after the mutation's tests
  # to put back what applying it changed (see
  # Mutator::LoadSources#restore_source). nil when a mutation was built
  # without one.
  attr_reader :subject, :operator_name, :parse_status, :location, :restore_source

  def initialize(subject:, operator_name:, sources:, location:,
                 slice: nil, parse_status: :ok, eval_source: nil, restore_source: nil)
    @subject = subject
    @operator_name = operator_name
    @sources = sources
    @location = location
    @slice = slice || NO_SLICE
    @parse_status = parse_status
    @eval_source = eval_source
    @restore_source = restore_source
    @diff = nil
  end

  def original_source
    @sources.original
  end

  def mutated_source
    @sources.mutated
  end

  # Source to feed to the load-time evaluator. Defaults to mutated_source
  # when no pre-eval transform was applied at generation time. Mutator::Base
  # populates this with the neutralized version (top-level idempotency-
  # violating calls replaced with `nil`) so the worker eval doesn't re-run
  # them. The neutralization Prism parse happens once at generation time,
  # not per worker iteration.
  def eval_source
    @eval_source || mutated_source
  end

  def original_slice
    @slice.original
  end

  def mutated_slice
    @slice.mutated
  end

  def file_path
    @location.file_path
  end

  def line
    @location.line
  end

  def column
    @location.column
  end

  def changed_lines
    @location.lines
  end

  def unparseable?
    @parse_status == :unparseable
  end

  def diff
    @diff ||= compute_diff
  end

  def unified_diff
    return @unified_diff if defined?(@unified_diff)

    @unified_diff = compute_unified_diff
  end

  def strip_sources!
    diff # ensure diff is cached before clearing sources
    @sources = STRIPPED_SOURCES
  end

  def to_s
    "#{operator_name}: #{file_path}:#{line}"
  end

  private

  def compute_diff
    LineDiff.call(original_source, mutated_source)
  end

  def compute_unified_diff
    return nil if @slice == NO_SLICE

    original_lines = @slice.original.lines
    mutated_lines = @slice.mutated.lines
    [
      "--- a/#{file_path}",
      "+++ b/#{file_path}",
      "@@ -#{line},#{original_lines.length} +#{line},#{mutated_lines.length} @@",
      unified_diff_body(original_lines, mutated_lines)
    ].reject(&:empty?).join("\n")
  end

  def unified_diff_body(original_lines, mutated_lines)
    ::Diff::LCS.sdiff(original_lines, mutated_lines).map { |c| format_sdiff_change(c) }.join("\n")
  end

  def format_sdiff_change(change)
    case change.action
    when "=" then " #{change.old_element.chomp}"
    when "-" then "-#{change.old_element.chomp}"
    when "+" then "+#{change.new_element.chomp}"
    when "!" then "-#{change.old_element.chomp}\n+#{change.new_element.chomp}"
    end
  end
end

require_relative "mutation/line_diff"
