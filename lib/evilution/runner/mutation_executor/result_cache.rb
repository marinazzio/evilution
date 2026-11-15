# frozen_string_literal: true

require_relative "../mutation_executor"
require_relative "../../result/mutation_result"
require_relative "../../infra_crash"

class Evilution::Runner::MutationExecutor::ResultCache
  Partition = Data.define(:uncached_indices, :cached_results)

  def initialize(backend)
    @backend = backend
  end

  # time_limit: the longest the mutation's test run would be allowed now; nil
  # when it would run without a limit.
  def fetch(mutation, time_limit:)
    return nil unless @backend

    data = @backend.fetch(mutation)
    return nil unless data
    return nil unless reusable?(data, time_limit)

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
    return unless result.killed? || result.timeout?
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

  # A kill that came from an infrastructure crash is not a verdict about the
  # mutation, and the cache keeps no error class to tell them apart later. It
  # is left out so the next fetch does not hand back a plain `:killed`, which
  # would defeat both the demotion to neutral and the serial retry
  # (EV-j0bv / GH #1607).
  def infra_crash?(result)
    Evilution::InfraCrash.class_name?(result.error_class)
  end

  # time_limit_for: answers the time limit #fetch is to compare against for
  # each mutation.
  def partition(batch, packer:, time_limit_for:)
    uncached_indices = []
    cached_results = {}

    batch.each_with_index do |mutation, i|
      if mutation.unparseable?
        cached_results[i] = packer.compact(unparseable_result(mutation))
        next
      end

      cached = fetch(mutation, time_limit: time_limit_for.call(mutation))
      if cached
        cached_results[i] = packer.compact(cached)
      else
        uncached_indices << i
      end
    end

    Partition.new(uncached_indices: uncached_indices, cached_results: cached_results)
  end

  private

  # A kill stands whatever the limit is now. A timeout says only that the run
  # needed more than the limit it had, so it answers for a run that would get
  # no more time than that; one that does not record its limit answers for none.
  def reusable?(data, time_limit)
    case data[:status]
    when :killed then true
    when :timeout then timeout_reusable?(data[:time_limit], time_limit)
    else false
    end
  end

  def timeout_reusable?(cached_limit, time_limit)
    cached_limit.is_a?(Numeric) && time_limit.is_a?(Numeric) && time_limit <= cached_limit
  end

  def unparseable_result(mutation)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :unparseable)
  end
end
