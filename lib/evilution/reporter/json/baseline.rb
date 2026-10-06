# frozen_string_literal: true

require_relative "../json"

# The summary fields that speak for a red baseline: the survivors it took out
# of the score, and why each spec file was red -- which is what tells real gaps
# from a baseline that failed on its own. Each is present only when there is
# something to say.
class Evilution::Reporter::JSON::Baseline
  def call(summary)
    fields = {}
    fields[:baseline_neutralized] = summary.baseline_neutralized if summary.baseline_neutralized.positive?
    fields[:baseline_failures] = summary.baseline_failures.map(&:to_h) unless summary.baseline_failures.empty?
    fields
  end
end
