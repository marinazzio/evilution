# frozen_string_literal: true

require_relative "subject_score"

# Groups mutation results by the subject they belong to and scores each one.
#
# Same denominator as the run's own score: statuses that carry no verdict
# (unresolved, neutral, equivalent, errored, unparseable) are left out of it, so
# a subject those account for entirely reports as unreached rather than as a
# perfect score over nothing.
class Evilution::Result::SubjectScorer
  VERDICT_STATUSES = %i[killed survived timeout].freeze
  private_constant :VERDICT_STATUSES

  def call(results)
    grouped = results.group_by { |result| [result.mutation.file_path, result.mutation.subject.name] }

    grouped
      .map { |(file_path, name), subject_results| score_for(name, file_path, subject_results) }
      .sort_by { |score| [score.file_path, score.name] }
  end

  private

  def score_for(name, file_path, results)
    verdicts = results.count { |result| VERDICT_STATUSES.include?(result.status) }

    Evilution::Result::SubjectScore.new(
      name: name,
      file_path: file_path,
      total: results.length,
      killed: results.count(&:killed?),
      verified: verdicts,
      survived: results.count(&:survived?)
    )
  end
end
