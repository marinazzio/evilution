# frozen_string_literal: true

require_relative "../sections"

class Evilution::Reporter::HTML::Sections::TruncationNotice < Evilution::Reporter::HTML::Section
  template "truncation_notice"

  def initialize(summary)
    @summary = summary
  end

  def self.render_if(summary)
    return "" unless summary.truncated?

    new(summary).render
  end
end
