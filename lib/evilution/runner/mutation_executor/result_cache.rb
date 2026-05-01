# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "../../result/mutation_result"

class Evilution::Runner::MutationExecutor::ResultCache
  CACHEABLE_STATUSES = %i[killed timeout].freeze
  private_constant :CACHEABLE_STATUSES

  def initialize(backend)
    @backend = backend
  end

  def fetch(mutation)
    return nil unless @backend

    data = @backend.fetch(mutation)
    return nil unless data
    return nil unless CACHEABLE_STATUSES.include?(data[:status])

    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: data[:status],
      duration: data[:duration],
      killing_test: data[:killing_test],
      test_command: data[:test_command]
    )
  end

  def store(mutation, result)
    return unless @backend
    return unless result.killed? || result.timeout?

    @backend.store(mutation,
                   status: result.status,
                   duration: result.duration,
                   killing_test: result.killing_test,
                   test_command: result.test_command)
  end

  def partition(batch, packer:)
    uncached_indices = []
    cached_results = {}

    batch.each_with_index do |mutation, i|
      if mutation.unparseable?
        cached_results[i] = packer.compact(unparseable_result(mutation))
        next
      end

      cached = fetch(mutation)
      if cached
        cached_results[i] = packer.compact(cached)
      else
        uncached_indices << i
      end
    end

    [uncached_indices, cached_results]
  end

  private

  def unparseable_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :unparseable)
  end
end
