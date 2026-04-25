# frozen_string_literal: true

require_relative "../rspec"

class Evilution::Integration::RSpec::TestFileResolver
  def initialize(test_files:, spec_selector:, related_spec_heuristic:,
                 related_specs_heuristic_enabled:, fallback_to_full_suite:, warner:)
    @test_files = test_files
    @spec_selector = spec_selector
    @related_spec_heuristic = related_spec_heuristic
    @related_specs_heuristic_enabled = related_specs_heuristic_enabled
    @fallback_to_full_suite = fallback_to_full_suite
    @warner = warner
  end

  def call(mutation)
    return @test_files if @test_files

    resolved = Array(@spec_selector.call(mutation.file_path))
    if resolved.empty?
      @warner.call(mutation.file_path, fallback_to_full_suite: @fallback_to_full_suite)
      return @fallback_to_full_suite ? ["spec"] : nil
    end

    return resolved unless @related_specs_heuristic_enabled

    related = @related_spec_heuristic.call(mutation)
    (resolved + related).uniq
  end
end
