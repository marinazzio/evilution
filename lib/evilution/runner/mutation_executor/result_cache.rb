# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "../../result/mutation_result"
require_relative "../../infra_crash"

class Evilution::Runner::MutationExecutor::ResultCache
  # The verdicts about a mutation. A survivor is kept too: its key changes
  # with the subject and its spec files, so a test that would now kill it
  # re-runs it.
  CACHEABLE_STATUSES = %i[killed survived timeout].freeze
  private_constant :CACHEABLE_STATUSES

  Partition = Data.define(:uncached_indices, :cached_results)

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
      test_command: data[:test_command],
      time_limit: data[:time_limit]
    )
  end

  def store(mutation, result)
    return unless @backend
    return unless CACHEABLE_STATUSES.include?(result.status)
    return if infra_crash?(result)
    # Nor is one where only already-failing examples failed: the baseline
    # that says so belongs to this run, and the cache keeps no trace of it.
    return if result.known_failures_only?

    @backend.store(mutation,
                   status: result.status,
                   duration: result.duration,
                   killing_test: result.killing_test,
                   test_command: result.test_command,
                   time_limit: result.time_limit)
  end

  # Writes out what the run stored (see Evilution::Cache#flush).
  def flush
    return unless @backend

    @backend.flush
  end

  # A kill that came from an infrastructure crash is not a verdict about the
  # mutation, and the cache keeps no error class to tell them apart later. It
  # is left out so the next fetch does not hand back a plain `:killed`, which
  # would defeat both the demotion to neutral and the serial retry
  # (EV-j0bv / GH #1607).
  def infra_crash?(result)
    Evilution::InfraCrash.class_name?(result.error_class)
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

    Partition.new(uncached_indices: uncached_indices, cached_results: cached_results)
  end

  private

  def unparseable_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :unparseable)
  end
end
