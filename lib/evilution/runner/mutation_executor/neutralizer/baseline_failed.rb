# frozen_string_literal: true

require_relative "../neutralizer"
require_relative "../../../result/mutation_result"
require_relative "../../../result/neutral_reason"

# Reclassifies a kill as :neutral when the tests failed on nothing but
# examples that were already failing before any mutation ran.
#
# Such an example fails whatever the mutation is, so every mutation it runs
# against would count as killed and a red spec file would score full marks.
# The failure says nothing about the mutation: it has no verdict.
#
# A survivor is left alone, whatever the baseline did. Its tests passed, the
# examples that were red in the baseline included, so the gap it reports is
# real -- and neutralizing it, as used to happen for every survivor a red spec
# file covered, hid exactly the mutations a reader needs to see.
class Evilution::Runner::MutationExecutor::Neutralizer::BaselineFailed
  def initialize(config:, spec_resolver:, fallback_dir:)
    @config = config
    @spec_resolver = spec_resolver
    @fallback_dir = fallback_dir
  end

  def call(result, baseline_result:)
    return result unless result.killed? && result.known_failures_only?

    neutralize(result, red_spec(result, baseline_result))
  end

  private

  # The red spec file to name: one covering the mutated source. A run given
  # its spec files explicitly has no single one to point at.
  def red_spec(result, baseline_result)
    return nil if @config.spec_files.any? || baseline_result.nil?

    failed = baseline_result.failed_spec_files
    covering_specs(result.mutation.file_path).find { |spec| failed.include?(spec) }
  end

  # The spec files the baseline ran for this source: every file the resolver
  # returns (a spec_selector may map one source to several), or the fallback
  # directory when nothing resolves -- but only if the run falls back to the
  # full suite; otherwise the baseline never ran it.
  def covering_specs(file_path)
    specs = Array(@spec_resolver.call(file_path))
    return specs unless specs.empty?

    @config.fallback_to_full_suite? ? [@fallback_dir] : []
  end

  # The spec that was already red is the fact a reader needs: it says what to
  # fix before the run can say anything about these mutations.
  def neutralize(result, spec_file)
    Evilution::Result::MutationResult.new(
      mutation: result.mutation,
      status: :neutral,
      duration: result.duration,
      test_command: result.test_command,
      memory: result.memory,
      error: result.error,
      neutral_reason: Evilution::Result::NeutralReason.baseline_failure(spec_file)
    )
  end
end
