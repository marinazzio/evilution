# frozen_string_literal: true

require_relative "coverage_gap"

class Evilution::Result::CoverageGapGrouper
  def call(survived_results)
    grouped = survived_results.group_by do |r|
      [r.mutation.file_path, r.mutation.subject.name, r.mutation.line]
    end

    gaps = grouped.map do |(file_path, subject_name, line), results|
      Evilution::Result::CoverageGap.new(
        file_path: file_path,
        subject_name: subject_name,
        line: line,
        mutation_results: results
      )
    end

    gaps.sort_by { |gap| [gap.file_path, gap.line, gap.subject_name] }
  end
end
