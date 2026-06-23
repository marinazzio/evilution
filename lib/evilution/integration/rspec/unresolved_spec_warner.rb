# frozen_string_literal: true

require_relative "../rspec"

class Evilution::Integration::RSpec::UnresolvedSpecWarner
  def initialize
    @warned = Set.new
  end

  def call(file_path, fallback_to_full_suite:)
    return if @warned.include?(file_path)

    @warned << file_path
    warn message(file_path, fallback_to_full_suite)
  end

  private

  # When already falling back the suite is running, so only the explicit-spec
  # hint is useful. Otherwise the mutation is skipped :unresolved — name BOTH
  # recovery paths, since behaviour-named layouts (specs not mirroring the lib
  # path, e.g. aasm's base.rb) never auto-resolve (EV-ajby / GH #1376).
  def message(file_path, fallback_to_full_suite)
    if fallback_to_full_suite
      "[evilution] No matching spec found for #{file_path}, running full suite. " \
        "Use --spec to specify the spec file."
    else
      "[evilution] No matching spec found for #{file_path}, marking mutation unresolved. " \
        "Use --spec to specify the spec file, or --fallback-full-suite to run the whole suite."
    end
  end
end
