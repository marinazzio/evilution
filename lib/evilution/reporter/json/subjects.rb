# frozen_string_literal: true

require_relative "../json"

# The per-subject rows of a JSON report.
#
# Every subject is listed, whether or not it needs attention: a consumer that
# wants only the gaps filters on `reached` and `score`, while one asserting that
# a method is covered at all needs to see the rest (EV-nlx1 / GH #1605).
class Evilution::Reporter::JSON::Subjects
  def call(summary)
    summary.subject_scores.map { |score| row(score) }
  end

  private

  def row(score)
    {
      name: score.name,
      file: score.file_path,
      total: score.total,
      killed: score.killed,
      verified: score.verified,
      survived: score.survived,
      score: score.score.round(4),
      reached: score.reached?
    }
  end
end
