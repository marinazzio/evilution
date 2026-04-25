# frozen_string_literal: true

require_relative "../../result/mutation_result"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass
class Evilution::Runner::MutationExecutor; end unless defined?(Evilution::Runner::MutationExecutor) # rubocop:disable Lint/EmptyClass

class Evilution::Runner::MutationExecutor::ResultPacker
  def compact(result)
    {
      status: result.status,
      duration: result.duration,
      killing_test: result.killing_test,
      test_command: result.test_command,
      child_rss_kb: result.child_rss_kb,
      memory_delta_kb: result.memory_delta_kb,
      parent_rss_kb: result.parent_rss_kb,
      error_message: result.error_message,
      error_class: result.error_class,
      error_backtrace: result.error_backtrace
    }
  end

  def rebuild(mutation, data)
    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: data[:status],
      duration: data[:duration],
      killing_test: data[:killing_test],
      test_command: data[:test_command],
      child_rss_kb: data[:child_rss_kb],
      memory_delta_kb: data[:memory_delta_kb],
      parent_rss_kb: data[:parent_rss_kb],
      error_message: data[:error_message],
      error_class: data[:error_class],
      error_backtrace: data[:error_backtrace]
    )
  end
end
