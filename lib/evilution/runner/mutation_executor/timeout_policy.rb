# frozen_string_literal: true

require_relative "../mutation_executor"

# Chooses the time limit each mutation's test run gets.
#
# One fixed limit makes a mutant that loops cost the whole limit even when its
# spec file passes in a fraction of a second. When the run measured a baseline,
# the limit follows the time the mutation's own spec files took there instead
# (Adaptive). A timeout the user gave keeps winning, and anything the baseline
# cannot vouch for keeps the fixed limit.
module Evilution::Runner::MutationExecutor::TimeoutPolicy
  # The pool's deadline for an item is a backstop for a worker that stops
  # answering, so it sits well past the limit the worker enforces itself.
  ITEM_TIMEOUT_FACTOR = 2

  # Autoloaded rather than required at the bottom: each policy file requires
  # this one, and requiring it while it is still loading is a circular require,
  # which Ruby warns about -- and a project that turns warnings into exceptions
  # loads this after its spec helper did so.
  autoload :Base, File.expand_path("timeout_policy/base", __dir__)
  autoload :Fixed, File.expand_path("timeout_policy/fixed", __dir__)
  autoload :Adaptive, File.expand_path("timeout_policy/adaptive", __dir__)

  def self.build(config, baseline_result)
    fixed = Fixed.new(config.timeout)
    return fixed unless adaptive?(config, baseline_result)

    Adaptive.new(
      fallback: fixed,
      spec_durations: baseline_result.spec_file_durations,
      failed_spec_files: baseline_result.failed_spec_files,
      spec_selector: config.spec_selector,
      factor: config.timeout_factor,
      floor: config.timeout_floor,
      ceiling: config.timeout_ceiling
    )
  end

  # The related-specs heuristic adds spec files per mutation that the baseline
  # never ran, so there is no time to scale for them.
  def self.adaptive?(config, baseline_result)
    config.adaptive_timeout? && !baseline_result.nil? && !config.related_specs_heuristic?
  end
  private_class_method :adaptive?
end
