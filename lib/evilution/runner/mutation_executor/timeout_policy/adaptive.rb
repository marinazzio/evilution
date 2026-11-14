# frozen_string_literal: true

require_relative "base"

# A limit per mutation of `factor` times the baseline time of the spec files it
# runs, kept between `floor` and `ceiling`.
#
# The baseline ran each spec file in a forked process of its own, so its time
# already holds the fork and the loading of the file. The factor leaves room
# for what the baseline did not see: a mutant that legitimately slows the code
# down, the re-run of a survivor against its whole spec files, and workers
# competing for the CPU under --jobs. The floor covers spec files so fast that
# scheduling noise outweighs them.
#
# A mutation keeps the fallback limit when the baseline cannot vouch for its
# spec files: none resolve (the run would fall back to the whole suite, or
# report it unresolved), one of them has no baseline time, or one of them
# failed in the baseline and so may have stopped early.
class Evilution::Runner::MutationExecutor::TimeoutPolicy::Adaptive < Evilution::Runner::MutationExecutor::TimeoutPolicy::Base
  def initialize(fallback:, spec_durations:, failed_spec_files:, spec_selector:, factor:, floor:, ceiling:)
    super()
    @fallback = fallback
    @spec_durations = spec_durations
    @failed_spec_files = failed_spec_files
    @spec_selector = spec_selector
    @factor = factor
    @floor = floor
    @ceiling = ceiling
  end

  def call(mutation)
    seconds = baseline_seconds(Array(@spec_selector.call(mutation.file_path)))
    return @fallback.call(mutation) if seconds.nil?

    (seconds * @factor).clamp(@floor, @ceiling)
  end

  private

  def baseline_seconds(spec_files)
    return nil if spec_files.empty?
    return nil if spec_files.any? { |spec_file| @failed_spec_files.include?(spec_file) }

    durations = spec_files.map { |spec_file| @spec_durations[spec_file] }
    return nil if durations.any?(nil)

    durations.sum
  end
end
