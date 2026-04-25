# frozen_string_literal: true

require_relative "../../../result/mutation_result"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass
class Evilution::Runner::MutationExecutor; end unless defined?(Evilution::Runner::MutationExecutor) # rubocop:disable Lint/EmptyClass
module Evilution::Runner::MutationExecutor::Neutralizer; end unless defined?(Evilution::Runner::MutationExecutor::Neutralizer)

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
      child_rss_kb: result.child_rss_kb,
      memory_delta_kb: result.memory_delta_kb,
      parent_rss_kb: result.parent_rss_kb,
      error_message: result.error_message,
      error_class: result.error_class,
      error_backtrace: result.error_backtrace
    )
  end
end
