# frozen_string_literal: true

require_relative "../sections"

# The mutations no test executes the line of: never run, scored as survivors.
class Evilution::Reporter::HTML::Sections::UncoveredDetails < Evilution::Reporter::HTML::Section
  template "uncovered_details"

  def self.render_if(uncovered)
    return "" if uncovered.empty?

    new(uncovered).render
  end

  def initialize(uncovered)
    @uncovered = uncovered
  end

  private

  attr_reader :uncovered

  def sorted
    uncovered.sort_by { |r| [r.mutation.line, r.mutation.operator_name] }
  end
end
