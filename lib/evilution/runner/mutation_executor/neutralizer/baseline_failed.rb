# frozen_string_literal: true

require_relative "../neutralizer"
require_relative "../../../result/mutation_result"

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
    else
      spec_file = @spec_resolver.call(result.mutation.file_path) || @fallback_dir
      should_neutralize = baseline_result.failed_spec_files.include?(spec_file)
    end
    return result unless should_neutralize

    neutralize(result)
  end

  private

  def neutralize(result)
    Evilution::Result::MutationResult.new(
      mutation: result.mutation,
      status: :neutral,
      duration: result.duration,
      test_command: result.test_command,
      memory: result.memory,
      error: result.error
    )
  end
end
