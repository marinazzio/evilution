# frozen_string_literal: true

require "diff/lcs"
require "diff/lcs/hunk"

class Evilution::Mutation
  attr_reader :subject, :operator_name, :original_source,
              :mutated_source, :file_path, :line, :column

  def initialize(subject:, operator_name:, original_source:, mutated_source:, file_path:, line:, column: 0)
    @subject = subject
    @operator_name = operator_name
    @original_source = original_source
    @mutated_source = mutated_source
    @file_path = file_path
    @line = line
    @column = column
    @diff = nil
  end

  def diff
    @diff ||= compute_diff
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

  public

  def to_s
    "#{operator_name}: #{file_path}:#{line}"
  end
end
