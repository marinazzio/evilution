# frozen_string_literal: true

require_relative "../work_queue"
require_relative "../../child_output"
require_relative "../../process_supervisor"
require_relative "../../temp_dir_tracker"
require_relative "channel"
require_relative "channel/frame"

class Evilution::Parallel::WorkQueue::Worker
  Timing = Data.define(:busy, :wall)

  attr_reader :pid, :worker_index, :in_flight_indices
  attr_accessor :items_completed, :pending, :busy_time, :wall_time, :deadline

  # EV-dg69 / EV-5rrh step 3: the supervisor owns the worker's process-group
  # isolation, signal-safe registry, group-kill and reap. spawn passes
  # isolate_in_child: false so the worker becomes its own group leader only
  # parent-side, AFTER the supervisor has registered it -- preserving the
  # EV-jwao register-before-isolate ordering (the trap can never see a leader
  # missing from the registry). EV-cnx8 group-leadership (so #kill sweeps the
  # whole subtree) is still established, now by the supervisor's parent-side
  # setpgid.
  def self.spawn(worker_index:, hooks:, supervisor: Evilution::ProcessSupervisor.new, &block)
    cmd_read, cmd_write = IO.pipe
    res_read, res_write = IO.pipe
    [cmd_read, cmd_write, res_read, res_write].each(&:binmode)

    handle = supervisor.spawn(isolate_in_child: false) do
      cmd_write.close
      res_read.close
      install_child_signal_handlers
      ENV["TEST_ENV_NUMBER"] = test_env_number_for(worker_index)
      Evilution::ChildOutput.redirect!
      Loop.run(cmd_read, res_write, hooks: hooks, &block)
    end

    cmd_read.close
    res_write.close
    new(handle:, supervisor:, cmd_write:, res_read:, worker_index:)
  end

  # EV-7a91: a worker is the parent of the inner per-mutation Fork children it
  # spawns, and those children are their own process-group leaders (EV-2sh8), so
  # the Runner's group-kill of the worker never reaches them. On a terminal
  # INT/TERM the worker must therefore tear down AND reap the inner children it
  # owns before it dies, or they survive as zombies (their parent gone) until an
  # ancestor exits. cleanup_all clears any per-mutation sandbox dirs the inner
  # children registered in this worker's TempDirTracker.
  def self.install_child_signal_handlers
    %w[INT TERM].each do |sig|
      Signal.trap(sig) do
        Evilution::TempDirTracker.cleanup_all
        Evilution::ProcessSupervisor.kill_and_reap_all
        Signal.trap(sig, "DEFAULT")
        Process.kill(sig, Process.pid)
      end
    end
  end

  # EV-kdns / GH #817: translate 0-based worker slot to parallel_tests'
  # TEST_ENV_NUMBER convention ("" for slot 0, "2" for slot 1, ...). Rails
  # apps interpolating TEST_ENV_NUMBER into database.yml get per-worker
  # SQLite files, avoiding lock contention under jobs > 1.
  def self.test_env_number_for(worker_index)
    worker_index.zero? ? "" : (worker_index + 1).to_s
  end

  def initialize(handle:, supervisor:, cmd_write:, res_read:, worker_index:)
    @handle = handle
    @supervisor = supervisor
    @pid = handle.pid
    @cmd_write = cmd_write
    @res_read = res_read
    @worker_index = worker_index
    @items_completed = 0
    @pending = 0
    @busy_time = 0.0
    @wall_time = 0.0
    @in_flight_indices = []
    @deadline = nil
  end

  def res_io
    @res_read
  end

  def send_item(index, item)
    Evilution::Parallel::WorkQueue::Channel.write(@cmd_write, [index, item])
    @pending += 1
    @in_flight_indices << index
  end

  def read_result
    Evilution::Parallel::WorkQueue::Channel.read(@res_read)
  end

  def shutdown
    Evilution::Parallel::WorkQueue::Channel.write(@cmd_write, Evilution::Parallel::WorkQueue::SHUTDOWN)
  rescue Errno::EPIPE
    nil
  end

  # SIGKILL the worker's whole process group (negative pid), reaping any
  # grandchildren it forked, with the bare pid as a fallback for the case where
  # the group is gone (already reaped, or setpgid did not take).
  def kill
    @supervisor.signal_group("KILL", @handle)
  end

  def close_pipes
    @cmd_write.close unless @cmd_write.closed?
    @res_read.close unless @res_read.closed?
  end

  # Reap the leader and drop it from the registry so the trap never signals a
  # group whose pid the OS may have recycled. ECHILD-tolerant; unregister is a
  # no-op if it was never registered.
  def reap
    @supervisor.reap(@handle)
  end

  def retire
    shutdown
    timing = drain_stats
    close_pipes
    reap
    @busy_time = timing.busy
    @wall_time = timing.wall
    to_stat
  end

  def to_stat
    Evilution::Parallel::WorkQueue::WorkerStat.new(
      @pid, @items_completed, @busy_time || 0.0, @wall_time || 0.0
    )
  end

  private

  def drain_stats
    zero = Timing.new(busy: 0.0, wall: 0.0)
    return zero unless @res_read.wait_readable(Evilution::Parallel::WorkQueue::TIMING_GRACE_PERIOD)

    message = read_result
    return zero if message.nil?

    tag, busy, wall = message
    return zero unless tag == Evilution::Parallel::WorkQueue::STATS

    Timing.new(busy: busy, wall: wall)
  end
end
