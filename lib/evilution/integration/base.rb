# frozen_string_literal: true

require_relative "../integration"
require_relative "loading/mutation_applier"

class Evilution::Integration::Base
  def self.baseline_runner
    raise NotImplementedError, "#{name}.baseline_runner must be implemented"
  end

  def self.baseline_options
    raise NotImplementedError, "#{name}.baseline_options must be implemented"
  end

  def initialize(hooks: nil, mutation_applier: Evilution::Integration::Loading::MutationApplier.new)
    @hooks = hooks
    @mutation_applier = mutation_applier
  end

  def call(mutation)
    ensure_framework_loaded
    fire_hook(:mutation_insert_pre, mutation: mutation, file_path: mutation.file_path)
    load_error, apply = timed { @mutation_applier.call(mutation) }
    return with_timings(load_error, apply: apply) if load_error

    fire_hook(:mutation_insert_post, mutation: mutation, file_path: mutation.file_path)
    result, tests = timed { Evilution.while_running_tests { run_tests(mutation) } }
    with_timings(result, apply: apply, tests: tests)
  ensure
    @mutation_applier.restore(mutation) unless restored_by_applier?(load_error)
  end

  private

  # An integration that re-runs a survivor reports that run's time as
  # `timings: { confirmation: }`; the rest of the test time is the first run.
  def with_timings(result, apply:, tests: nil)
    return result unless result.is_a?(Hash)

    reported = result[:timings].is_a?(Hash) ? result[:timings] : {}
    confirmation = reported[:confirmation]
    timings = { apply: apply }
    timings[:test_run] = tests - (confirmation || 0.0) if tests
    timings[:confirmation] = confirmation if confirmation
    result.merge(timings: timings)
  end

  # The block's value and the seconds it took.
  def timed
    started = monotonic_now
    value = yield
    [value, monotonic_now - started]
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # The applier evaluates the original to tell that a mutant broke the load of
  # its file; after that the file is as it was, and need not be restored again.
  def restored_by_applier?(load_error)
    return false if load_error.nil?

    load_error[:load_crashed] == true
  end

  def ensure_framework_loaded
    raise NotImplementedError, "#{self.class}#ensure_framework_loaded must be implemented"
  end

  def run_tests(_mutation)
    raise NotImplementedError, "#{self.class}#run_tests must be implemented"
  end

  def build_args(_mutation)
    raise NotImplementedError, "#{self.class}#build_args must be implemented"
  end

  def reset_state
    raise NotImplementedError, "#{self.class}#reset_state must be implemented"
  end

  def fire_hook(event, **payload)
    @hooks.fire(event, **payload) if @hooks
  end
end
