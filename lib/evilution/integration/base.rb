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

  # Fills whatever the integration caches per source or test file for the
  # given mutations. Called in the parent before any mutation runs, so forked
  # children inherit the caches instead of each filling its own and losing it.
  def warm_targeting(_mutations)
    nil
  end

  # Whether no test executes the line the mutation sits on, so it need not
  # run. Only an integration backed by line coverage can tell.
  def uncovered?(_mutation)
    false
  end

  # The ids of the tests that killed the next mutation's neighbours earlier in
  # the run, the most telling first. An integration that stops at the first
  # kill and can choose the order of its tests runs these first; the others
  # have nothing to do with them.
  def prioritize(_test_ids)
    nil
  end

  # Fills what loading a mutated file looks up on the heap (see
  # Loading::MutationApplier#warm). Called in the parent before any mutation
  # runs, for the same reason as #warm_targeting.
  def warm_loading
    @mutation_applier.warm
    nil
  end

  # The timing methods are taken as method objects before the mutation is
  # applied. When the file under mutation is this one, applying it replaces
  # them, and a mutant of the code that builds the result would otherwise
  # decide its own verdict. A method object keeps the definition the call
  # started with.
  def call(mutation)
    ensure_framework_loaded
    fire_insert_hook(:mutation_insert_pre, mutation)
    timed = timer
    attach_timings = method(:with_timings)
    load_error, apply = timed.call { @mutation_applier.call(mutation) }
    return attach_timings.call(load_error, apply: apply) if load_error

    fire_insert_hook(:mutation_insert_post, mutation)
    result, tests = timed.call { Evilution.while_running_tests { run_tests(mutation) } }
    attach_timings.call(result, apply: apply, tests: tests)
  ensure
    @mutation_applier.restore(mutation) if restore_needed?(load_error)
  end

  private

  # A process that ends with its mutation exits right after reporting it, so
  # nothing would run against the restored file; evaluating it again would
  # only delay the report.
  def restore_needed?(load_error)
    return false if Evilution.single_mutation_process?

    !restored_by_applier?(load_error)
  end

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

  # A callable returning the block's value and the seconds it took, bound to
  # the clock as it is now.
  def timer
    clock = method(:monotonic_now)
    lambda do |&block|
      started = clock.call
      value = block.call
      [value, clock.call - started]
    end
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

  def fire_insert_hook(event, mutation)
    fire_hook(event, mutation: mutation, file_path: mutation.file_path)
  end

  def fire_hook(event, **payload)
    @hooks.fire(event, **payload) if @hooks
  end
end
