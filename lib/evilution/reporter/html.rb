# frozen_string_literal: true

require_relative "../reporter"
require_relative "suggestion"
require_relative "html/escape"
require_relative "html/baseline_keys"
require_relative "html/report"

class Evilution::Reporter::HTML
  def initialize(baseline: nil, integration: :rspec)
    @suggestion = Evilution::Reporter::Suggestion.new(integration: integration)
    @baseline = baseline
    @baseline_keys = BaselineKeys.new(baseline)
  end

  def call(summary)
    Report.new(
      summary,
      baseline: @baseline,
      baseline_keys: @baseline_keys,
      suggestion: @suggestion
    ).render
  end
end
