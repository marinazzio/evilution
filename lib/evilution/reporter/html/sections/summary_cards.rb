# frozen_string_literal: true

require_relative "../sections"

class Evilution::Reporter::HTML::Sections::SummaryCards < Evilution::Reporter::HTML::Section
  template "summary_cards"

  def initialize(summary)
    @summary = summary
  end
end
