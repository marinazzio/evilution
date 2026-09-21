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

    if @config.spec_files.any?
      should_neutralize = true
      spec_file = nil
    else
      spec_file = @spec_resolver.call(result.mutation.file_path) || @fallback_dir
      should_neutralize = baseline_result.failed_spec_files.include?(spec_file)
    end
    return result unless should_neutralize

    neutralize(result, spec_file)
  end

  private

  # The spec that was already red is the fact a reader needs: it says what to
  # fix before the run can say anything about these mutations
  # (EV-5pob / GH #1606).
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
