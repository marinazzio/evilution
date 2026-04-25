# frozen_string_literal: true

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass
class Evilution::Runner::MutationExecutor; end unless defined?(Evilution::Runner::MutationExecutor) # rubocop:disable Lint/EmptyClass
module Evilution::Runner::MutationExecutor::Strategy; end unless defined?(Evilution::Runner::MutationExecutor::Strategy)

class Evilution::Runner::MutationExecutor::Strategy::Sequential
  def initialize(runner:, pipeline:, notifier:)
    @runner = runner
    @pipeline = pipeline
    @notifier = notifier
  end

  def call(mutations, baseline_result:, integration:)
    @notifier.start(mutations.length)
    results = []
    truncated = false

    mutations.each_with_index do |mutation, index|
      result = @runner.call(mutation, integration: integration)
      mutation.strip_sources!
      result = @pipeline.call(result, baseline_result: baseline_result)
      results << result

      if @notifier.notify(result, index + 1) == :truncate
        truncated = true
        break
      end
    end

    @notifier.finish
    [results, truncated]
  end
end
