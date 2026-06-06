# frozen_string_literal: true

require_relative "../work_queue"
require_relative "../../child_output"
require_relative "channel"
require_relative "channel/frame"
require_relative "worker_registry"

class Evilution::Parallel::WorkQueue::Worker
  Timing = Data.define(:busy, :wall)

  attr_reader :pid, :worker_index, :in_flight_indices
  attr_accessor :items_completed, :pending, :busy_time, :wall_time, :deadline

  def self.spawn(worker_index:, hooks:, &block)
    cmd_read, cmd_write = IO.pipe
    res_read, res_write = IO.pipe
    [cmd_read, cmd_write, res_read, res_write].each(&:binmode)

    pid = Process.fork do
      cmd_write.close
      res_read.close
      ENV["TEST_ENV_NUMBER"] = test_env_number_for(worker_index)
      Evilution::ChildOutput.redirect!
      Loop.run(cmd_read, res_write, hooks: hooks, &block)
    end

    cmd_read.close
    res_write.close
    # Register BEFORE isolating so the trap can never observe a worker that is
    # already its own group leader yet missing from the registry (EV-jwao race,
    # GH #1333 review): the spawn runs on the same main thread the trap
    # interrupts, so a signal arriving between setpgid and register would
    # otherwise leak a leader the trap cannot reach. Ordering register first
    # leaves only safe windows -- pre-setpgid the child still shares the parent
    # group and receives the terminal signal directly; once it is its own
    # leader the registry already lists it. Registering unconditionally is safe
    # because signal_all's kill(-pid) is a no-op (Errno::ESRCH) for a pid that
    # never became a group leader (setpgid failed).
    Evilution::Parallel::WorkQueue::WorkerRegistry.register(pid)
    isolate_process_group(pid)
    new(pid:, cmd_write:, res_read:, worker_index:)
  end

  # EV-cnx8 / GH #1324: make the worker its own process-group leader so #kill
  # can signal the whole subtree. A mutation's spec may fork a grandchild that
  # blocks (e.g. ConditionVariable#wait); when the dispatcher SIGKILLs a stuck
  # worker, that grandchild must die with it rather than orphan to init holding
  # memory/fds/connections. Done parent-side (before the child forks anything)
  # so a failure is visible here instead of being swallowed in the child.
  def self.isolate_process_group(pid)
    Process.setpgid(pid, pid)
  rescue Errno::EACCES, Errno::ESRCH
    # EACCES: child already exec'd/changed group; ESRCH: child already exited.
    # Both are benign -- reaping handles the child either way.
    nil
  rescue SystemCallError => e
    warn "evilution: could not isolate worker #{pid} into its own process " \
         "group (#{e.class}: #{e.message}); grandchildren may survive a kill."
  end

  # EV-kdns / GH #817: translate 0-based worker slot to parallel_tests'
  # TEST_ENV_NUMBER convention ("" for slot 0, "2" for slot 1, ...). Rails
  # apps interpolating TEST_ENV_NUMBER into database.yml get per-worker
  # SQLite files, avoiding lock contention under jobs > 1.
  def self.test_env_number_for(worker_index)
    worker_index.zero? ? "" : (worker_index + 1).to_s
  end

  def initialize(pid:, cmd_write:, res_read:, worker_index:)
    @pid = pid
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
  # grandchildren it forked. Falls back to the single pid if the group is gone
  # -- already reaped, or setpgid did not take in the child.
  def kill
    Process.kill("KILL", -@pid)
  rescue Errno::ESRCH
    kill_pid
  end

  def kill_pid
    Process.kill("KILL", @pid)
  rescue Errno::ESRCH
    nil
  end

  def close_pipes
    @cmd_write.close unless @cmd_write.closed?
    @res_read.close unless @res_read.closed?
  end

  def reap
    Process.wait(@pid)
  rescue Errno::ECHILD
    nil
  ensure
    # Drop the pgid once the leader is reaped so the trap never signals a group
    # whose pid the OS may have recycled. No-op if it was never registered.
    Evilution::Parallel::WorkQueue::WorkerRegistry.unregister(@pid)
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
