# frozen_string_literal: true

require_relative "../result"

# Where a run's time went, apart from what each mutation measured itself:
#
# - phases:              seconds per phase of the run, in the order they ran
# - baseline_spec_files: seconds the baseline spent on each spec file
# - workers:             one Parallel::WorkQueue::WorkerStat per worker process
#                        of a parallel run; empty for a sequential one
class Evilution::Result::RunTimings
  attr_reader :phases, :baseline_spec_files, :workers

  def initialize(phases: {}, baseline_spec_files: {}, workers: [])
    @phases = phases.freeze
    @baseline_spec_files = baseline_spec_files.freeze
    @workers = workers.freeze
    freeze
  end
end
