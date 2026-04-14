# frozen_string_literal: true

require_relative "../sections"
require_relative "../../../result/coverage_gap_grouper"
require_relative "survived_entry"

class Evilution::Reporter::HTML::Sections::SurvivedDetails < Evilution::Reporter::HTML::Section
  template "survived_details"

  def self.render_if(survived, suggestion:, baseline_keys:)
    return "" if survived.empty?

    new(survived, suggestion: suggestion, baseline_keys: baseline_keys).render
  end

  def initialize(survived, suggestion:, baseline_keys:)
    @survived = survived
    @suggestion = suggestion
    @baseline_keys = baseline_keys
  end

  private

  def gaps
    @gaps ||= Evilution::Result::CoverageGapGrouper.new.call(@survived)
  end

  def render_entry(result)
    Evilution::Reporter::HTML::Sections::SurvivedEntry.new(
      result,
      suggestion: @suggestion,
      baseline_keys: @baseline_keys
    ).render
  end
end
