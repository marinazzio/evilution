# frozen_string_literal: true

require_relative "../sections"

class Evilution::Reporter::HTML::Sections::UnparseableDetails < Evilution::Reporter::HTML::Section
  template "unparseable_details"

  def self.render_if(unparseable)
    return "" if unparseable.empty?

    new(unparseable).render
  end

  def initialize(unparseable)
    @unparseable = unparseable
  end

  private

  attr_reader :unparseable

  def sorted
    unparseable.sort_by { |r| [r.mutation.operator_name, r.mutation.line] }
  end
end
