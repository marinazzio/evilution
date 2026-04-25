# frozen_string_literal: true

require_relative "../../result/mutation_result"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass
class Evilution::Runner::MutationExecutor; end unless defined?(Evilution::Runner::MutationExecutor) # rubocop:disable Lint/EmptyClass

class Evilution::Runner::MutationExecutor::MutationRunner
  def initialize(config:, cache:, isolator:)
    @config = config
    @cache = cache
    @isolator = isolator
  end

  def call(mutation, integration:)
    return unparseable_result(mutation) if mutation.unparseable?

    cached = @cache.fetch(mutation)
    return cached if cached

    test_command = ->(m) { integration.call(m) }
    result = @isolator.call(mutation: mutation, test_command: test_command, timeout: @config.timeout)
    @cache.store(mutation, result)
    result
  end

  private

  def unparseable_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :unparseable)
  end
end
