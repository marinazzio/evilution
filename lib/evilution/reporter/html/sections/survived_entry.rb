# frozen_string_literal: true

require_relative "../sections"
require_relative "../diff_formatter"

class Evilution::Reporter::HTML::Sections::SurvivedEntry < Evilution::Reporter::HTML::Section
  template "survived_entry"

  def initialize(result, suggestion:, baseline_keys:)
    @result = result
    @suggestion = suggestion
    @baseline_keys = baseline_keys
  end

  private

  def regression?
    @baseline_keys.regression?(@result.mutation)
  end

  def entry_class
    regression? ? "survived-entry regression" : "survived-entry"
  end

  def regression_badge
    regression? ? ' <span class="regression-badge">NEW REGRESSION</span>' : ""
  end

  def suggestion_text
    @suggestion.suggestion_for(@result.mutation)
  end

  def diff_html
    Evilution::Reporter::HTML::DiffFormatter.call(@result.mutation.diff)
  end
end
