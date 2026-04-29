# frozen_string_literal: true

require_relative "../reporter"
require_relative "suggestion"

class Evilution::Reporter::HTML
  autoload :Escape, "evilution/reporter/html/escape"
  autoload :BaselineKeys, "evilution/reporter/html/baseline_keys"
  autoload :Section, "evilution/reporter/html/section"
  autoload :Sections, "evilution/reporter/html/sections"
  autoload :Stylesheet, "evilution/reporter/html/stylesheet"
  autoload :DiffFormatter, "evilution/reporter/html/diff_formatter"
  autoload :Report, "evilution/reporter/html/report"

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
