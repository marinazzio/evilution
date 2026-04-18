# frozen_string_literal: true

require_relative "../sections"

class Evilution::Reporter::HTML::Sections::UnresolvedDetails < Evilution::Reporter::HTML::Section
  template "unresolved_details"

  def self.render_if(unresolved)
    return "" if unresolved.empty?

    new(unresolved).render
  end

  def initialize(unresolved)
    @unresolved = unresolved
  end

  private

  attr_reader :unresolved

  def sorted
    unresolved.sort_by { |r| [r.mutation.operator_name, r.mutation.line] }
  end
end
