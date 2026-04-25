# frozen_string_literal: true

require_relative "../work_queue"

class Evilution::Parallel::WorkQueue
  WorkerStat = Struct.new(:pid, :items_completed, :busy_time, :wall_time) do
    def idle_time
      wall_time - busy_time
    end

    def utilization
      return 0.0 if wall_time.nil? || wall_time.zero?

      busy_time / wall_time
    end
  end
end
