# frozen_string_literal: true

require_relative "../result"

class Evilution::Result::CoverageGap
  attr_reader :file_path, :subject_name, :line, :mutation_results

  def initialize(file_path:, subject_name:, line:, mutation_results:)
    @file_path = file_path
    @subject_name = subject_name
    @line = line
    @mutation_results = mutation_results
    freeze
  end

  def operator_names
    mutation_results.map { |r| r.mutation.operator_name }.uniq
  end

  def primary_operator
    mutation_results.first.mutation.operator_name
  end

  def primary_diff
    mutation_results.first.mutation.diff
  end

  def count
    mutation_results.length
  end

  def single?
    count == 1
  end
end
