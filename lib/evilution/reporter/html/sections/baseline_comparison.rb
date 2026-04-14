# frozen_string_literal: true

require_relative "../sections"

class Evilution::Reporter::HTML::Sections::BaselineComparison < Evilution::Reporter::HTML::Section
  template "baseline_comparison"

  def self.render_if(baseline, summary)
    return "" unless baseline

    new(baseline, summary).render
  end

  def initialize(baseline, summary)
    @baseline = baseline
    @summary = summary
  end

  private

  def base_score
    (@baseline["summary"] || {})["score"] || 0.0
  end

  def head_score
    @summary.score
  end

  def delta
    head_score - base_score
  end

  def delta_str
    format("%+.2f%%", delta * 100)
  end

  def delta_class
    if delta.positive?
      "delta-positive"
    elsif delta.negative?
      "delta-negative"
    else
      "delta-neutral"
    end
  end
end
