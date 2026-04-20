# frozen_string_literal: true

require_relative "../sections"
require_relative "mutation_map"
require_relative "survived_details"
require_relative "error_details"
require_relative "neutral_details"
require_relative "unresolved_details"
require_relative "unparseable_details"

class Evilution::Reporter::HTML::Sections::FileSection < Evilution::Reporter::HTML::Section
  template "file_section"

  def initialize(path, results, suggestion:, baseline_keys:)
    @path = path
    @results = results
    @suggestion = suggestion
    @baseline_keys = baseline_keys
  end

  private

  def killed_count
    @results.count(&:killed?)
  end

  def survived_count
    @results.count(&:survived?)
  end

  def total
    @results.length
  end

  def map_html
    Evilution::Reporter::HTML::Sections::MutationMap.new(@results).render
  end

  def survived_html
    Evilution::Reporter::HTML::Sections::SurvivedDetails.render_if(
      @results.select(&:survived?),
      suggestion: @suggestion,
      baseline_keys: @baseline_keys
    )
  end

  def error_html
    Evilution::Reporter::HTML::Sections::ErrorDetails.render_if(@results.select(&:error?))
  end

  def neutral_html
    Evilution::Reporter::HTML::Sections::NeutralDetails.render_if(@results.select(&:neutral?))
  end

  def unresolved_html
    Evilution::Reporter::HTML::Sections::UnresolvedDetails.render_if(@results.select(&:unresolved?))
  end

  def unparseable_html
    Evilution::Reporter::HTML::Sections::UnparseableDetails.render_if(@results.select(&:unparseable?))
  end
end
