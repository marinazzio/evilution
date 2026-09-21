# frozen_string_literal: true

require_relative "../item_formatters"
require_relative "subject_score"

# The subjects of one file, under that file's name.
class Evilution::Reporter::CLI::ItemFormatters::SubjectScoreGroup
  def initialize(row: Evilution::Reporter::CLI::ItemFormatters::SubjectScore.new)
    @row = row
  end

  def format(scores)
    rows = scores.map { |score| @row.format(score) }
    ["  #{scores.first.file_path}", *rows].join("\n")
  end
end
