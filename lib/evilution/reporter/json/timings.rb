# frozen_string_literal: true

require_relative "../json"

# Where the run's time went: each phase of the run, each spec file of the
# baseline, each mutation phase summed over the mutations, and each worker of
# a parallel run with the share of its life it spent busy. Every section is
# always present, empty when the run did not measure it, so a consumer reads
# one shape.
class Evilution::Reporter::JSON::Timings
  def call(summary)
    timings = summary.timings
    {
      phases: timings.phases.transform_values { |seconds| seconds.round(4) },
      baseline: timings.baseline_spec_files.map { |file, seconds| { spec_file: file, duration: seconds.round(4) } },
      mutations: summary.mutation_timing_totals.transform_values { |seconds| seconds.round(4) },
      workers: timings.workers.map { |worker| worker_row(worker) }
    }
  end

  # The fields a mutation's row carries about its own time: where it went,
  # when the run measured it, and the limit it ran under, when it used it up.
  def mutation_fields(result)
    fields = {}
    fields[:time_limit] = result.time_limit.round(4) if result.time_limit
    timings = result.timings
    fields[:timings] = timings.to_h.transform_values { |seconds| seconds.round(4) } if timings
    fields
  end

  private

  def worker_row(worker)
    {
      pid: worker.pid,
      items: worker.items_completed,
      busy: worker.busy_time.round(4),
      wall: worker.wall_time.round(4),
      utilization: worker.utilization.round(4)
    }
  end
end
