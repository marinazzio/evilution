# frozen_string_literal: true

require "diff/lcs"

class Evilution::Mutation
  Sources = Data.define(:original, :mutated)
  Slice = Data.define(:original, :mutated)
  Location = Data.define(:file_path, :line, :column)

  attr_reader :subject, :operator_name, :parse_status, :location

  def initialize(subject:, operator_name:, sources:, location:, slice: nil, parse_status: :ok)
    @subject = subject
    @operator_name = operator_name
    @sources = sources
    @location = location
    @slice = slice
    @parse_status = parse_status
    @diff = nil
  end

  def original_source
    @sources&.original
  end

  def mutated_source
    @sources&.mutated
  end

  def original_slice
    @slice&.original
  end

  def mutated_slice
    @slice&.mutated
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
    @sources = nil
  end

  def to_s
    "#{operator_name}: #{file_path}:#{line}"
  end

  private

  def compute_diff
    original_lines = original_source.lines
    mutated_lines = mutated_source.lines
    diffs = ::Diff::LCS.diff(original_lines, mutated_lines)

    return "" if diffs.empty?

    result = []
    diffs.flatten(1).each do |change|
      case change.action
      when "-"
        result << "- #{change.element.chomp}"
      when "+"
        result << "+ #{change.element.chomp}"
      end
    end
    result.join("\n")
  end

  def compute_unified_diff
    return nil if @slice.nil?

    original_lines = @slice.original.lines
    mutated_lines = @slice.mutated.lines
    body = ::Diff::LCS.sdiff(original_lines, mutated_lines).map { |c| format_sdiff_change(c) }.join("\n")
    [
      "--- a/#{file_path}",
      "+++ b/#{file_path}",
      "@@ -#{line},#{original_lines.length} +#{line},#{mutated_lines.length} @@",
      body
    ].reject(&:empty?).join("\n")
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
