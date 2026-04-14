# frozen_string_literal: true

require_relative "section"
require_relative "stylesheet"
require_relative "baseline_keys"
require_relative "sections/header"
require_relative "sections/summary_cards"
require_relative "sections/baseline_comparison"
require_relative "sections/truncation_notice"
require_relative "sections/file_section"

class Evilution::Reporter::HTML::Report < Evilution::Reporter::HTML::Section
  template "report"

  def initialize(summary, baseline:, baseline_keys:, suggestion:)
    @summary = summary
    @baseline = baseline
    @baseline_keys = baseline_keys
    @suggestion = suggestion
  end

  private

  def stylesheet
    Evilution::Reporter::HTML::Stylesheet.call
  end

  def header
    Evilution::Reporter::HTML::Sections::Header.new(@summary).render
  end

  def summary_cards
    Evilution::Reporter::HTML::Sections::SummaryCards.new(@summary).render
  end

  def baseline_comparison
    Evilution::Reporter::HTML::Sections::BaselineComparison.render_if(@baseline, @summary)
  end

  def truncation_notice
    Evilution::Reporter::HTML::Sections::TruncationNotice.render_if(@summary)
  end

  def file_sections
    files = group_by_file(@summary.results)
    return '<p class="empty">No mutations generated.</p>' if files.empty?

    files.map { |path, results| file_section(path, results) }.join("\n")
  end

  def file_section(path, results)
    Evilution::Reporter::HTML::Sections::FileSection.new(
      path, results,
      suggestion: @suggestion,
      baseline_keys: @baseline_keys
    ).render
  end

  def group_by_file(results)
    grouped = {}
    results.each do |result|
      path = result.mutation.file_path
      grouped[path] ||= []
      grouped[path] << result
    end
    grouped.sort_by { |path, _| path }.to_h
  end
end
