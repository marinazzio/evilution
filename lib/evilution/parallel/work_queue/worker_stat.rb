# frozen_string_literal: true

require_relative "../work_queue"

class Evilution::Parallel::WorkQueue
  WorkerStat = Struct.new(:pid, :items_completed, :busy_time, :wall_time) do
    # One stat per worker process, summed over every pool.map it served.
    def self.aggregate(stats)
      stats.group_by(&:pid).map do |pid, entries|
        new(pid, entries.sum(&:items_completed), entries.sum(&:busy_time), entries.sum(&:wall_time))
      end
    end

    def idle_time
      wall_time - busy_time
    end

    def utilization
      return 0.0 if wall_time.nil? || wall_time.zero?

      busy_time / wall_time
    end
  end
end
