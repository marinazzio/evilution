# frozen_string_literal: true

require_relative "../rspec"

class Evilution::Integration::RSpec::UnresolvedSpecWarner
  def initialize
    @warned = Set.new
  end

  def call(file_path, fallback_to_full_suite:)
    return if @warned.include?(file_path)

    @warned << file_path
    action = fallback_to_full_suite ? "running full suite" : "marking mutation unresolved"
    warn "[evilution] No matching spec found for #{file_path}, #{action}. " \
         "Use --spec to specify the spec file."
  end
end
