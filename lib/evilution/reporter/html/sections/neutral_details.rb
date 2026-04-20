# frozen_string_literal: true

require_relative "../sections"

class Evilution::Reporter::HTML::Sections::NeutralDetails < Evilution::Reporter::HTML::Section
  template "neutral_details"

  def self.render_if(neutral)
    return "" if neutral.empty?

    new(neutral).render
  end

  def initialize(neutral)
    @neutral = neutral
  end

  private

  attr_reader :neutral

  def sorted
    neutral.sort_by { |r| [r.mutation.operator_name, r.mutation.line] }
  end
end
