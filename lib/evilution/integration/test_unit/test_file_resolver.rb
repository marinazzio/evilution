# frozen_string_literal: true

require_relative "../test_unit"

# Resolves the list of test files to load for a given mutation. Encapsulates
# the explicit-override path, spec-selector lookup, fallback glob, and the
# warn-once behaviour for unresolved sources. The integration class would
# otherwise carry both per-instance test resolution state (@test_files,
# @spec_selector, @warned_files, @fallback_to_full_suite) and dispatch
# orchestration in the same object; splitting them gives the resolver its
# own change axis (e.g. adding new resolution heuristics) independent of
# the runner.
class Evilution::Integration::TestUnit::TestFileResolver
  def initialize(test_files:, spec_selector:, fallback_to_full_suite:)
    @test_files = test_files
    @spec_selector = spec_selector
    @fallback_to_full_suite = fallback_to_full_suite
    @warned_files = Set.new
  end

  # Returns the resolved file list, or nil if the source could not be
  # resolved and fallback is disabled.
  def call(mutation_file_path)
    return @test_files if @test_files

    resolved = Array(@spec_selector.call(mutation_file_path))
    return resolved unless resolved.empty?

    warn_unresolved(mutation_file_path)
    @fallback_to_full_suite ? glob_test_files : nil
  end

  private

  def glob_test_files
    files = Dir.glob("test/**/*_test.rb")
    files.empty? ? ["test"] : files
  end

  def warn_unresolved(file_path)
    return if @warned_files.include?(file_path)

    @warned_files << file_path
    action = @fallback_to_full_suite ? "running full suite" : "marking mutation unresolved"
    warn "[evilution] No matching test found for #{file_path}, #{action}. " \
         "Use --spec to specify the test file."
  end
end
