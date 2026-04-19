# frozen_string_literal: true

require "diff/lcs"
require "diff/lcs/hunk"

class Evilution::Mutation
  attr_reader :subject, :operator_name, :original_source,
              :mutated_source, :original_slice, :mutated_slice,
              :file_path, :line, :column, :parse_status

  # rubocop:disable Metrics/ParameterLists
  def initialize(subject:, operator_name:, original_source:, mutated_source:,
                 file_path:, line:, column: 0, original_slice: nil, mutated_slice: nil,
                 parse_status: :ok)
    # rubocop:enable Metrics/ParameterLists
    @subject = subject
    @operator_name = operator_name
    @original_source = original_source
    @mutated_source = mutated_source
    @original_slice = original_slice
    @mutated_slice = mutated_slice
    @file_path = file_path
    @line = line
    @column = column
    @parse_status = parse_status
    @diff = nil
  end

  def unparseable?
    @parse_status == :unparseable
  end

  def diff
    @diff ||= compute_diff
  end

  def unified_diff
    @unified_diff ||= compute_unified_diff
  end

  def strip_sources!
    diff # ensure diff is cached before clearing sources
    @original_source = nil
    @mutated_source = nil
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
    return nil if @original_slice.nil? || @mutated_slice.nil?

    original_lines = @original_slice.lines
    mutated_lines = @mutated_slice.lines
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

  public

  def to_s
    "#{operator_name}: #{file_path}:#{line}"
  end
end
