# frozen_string_literal: true

require_relative "../sections"
require_relative "error_entry"

class Evilution::Reporter::HTML::Sections::ErrorDetails < Evilution::Reporter::HTML::Section
  template "error_details"

  def self.render_if(errored)
    return "" if errored.empty?

    new(errored).render
  end

  def initialize(errored)
    @errored = errored
  end

  private

  attr_reader :errored

  def sorted
    errored.sort_by { |r| [r.mutation.operator_name, r.mutation.line] }
  end

  def render_entry(result)
    Evilution::Reporter::HTML::Sections::ErrorEntry.new(result).render
  end
end
