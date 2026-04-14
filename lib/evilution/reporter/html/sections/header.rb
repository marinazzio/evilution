# frozen_string_literal: true

require_relative "../sections"
require_relative "../../../version"

class Evilution::Reporter::HTML::Sections::Header < Evilution::Reporter::HTML::Section
  template "header"

  def initialize(summary)
    @summary = summary
  end

  private

  def score_pct
    format("%.2f%%", @summary.score * 100)
  end

  def score_css_class
    score = @summary.score
    if score >= 0.8
      "score-high"
    elsif score >= 0.5
      "score-medium"
    else
      "score-low"
    end
  end
end
