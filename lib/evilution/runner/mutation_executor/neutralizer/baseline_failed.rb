# frozen_string_literal: true

require_relative "../neutralizer"
require_relative "../../../result/mutation_result"
require_relative "../../../result/neutral_reason"

class Evilution::Runner::MutationExecutor::Neutralizer::BaselineFailed
  def initialize(config:, spec_resolver:, fallback_dir:)
    @config = config
    @spec_resolver = spec_resolver
    @fallback_dir = fallback_dir
  end

  def call(result, baseline_result:)
    return result unless result.survived? && baseline_result && baseline_result.failed?

    return neutralize(result, nil) if @config.spec_files.any?

    failed = baseline_result.failed_spec_files
    spec_file = covering_specs(result.mutation.file_path).find { |spec| failed.include?(spec) }
    return result unless spec_file

    neutralize(result, spec_file)
  end

  private

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
