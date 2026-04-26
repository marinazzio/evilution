# frozen_string_literal: true

require_relative "../work_queue"
require_relative "../../child_output"
require_relative "channel"
require_relative "channel/frame"

class Evilution::Parallel::WorkQueue::Worker
  attr_reader :pid, :worker_index
  attr_accessor :items_completed, :pending, :busy_time, :wall_time

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
    new(pid: pid, cmd_write: cmd_write, res_read: res_read, worker_index: worker_index)
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
  end

  def res_io
    @res_read
  end

  def send_item(index, item)
    Evilution::Parallel::WorkQueue::Channel.write(@cmd_write, [index, item])
    @pending += 1
  end

  def read_result
    Evilution::Parallel::WorkQueue::Channel.read(@res_read)
  end

  def shutdown
    Evilution::Parallel::WorkQueue::Channel.write(@cmd_write, Evilution::Parallel::WorkQueue::SHUTDOWN)
  rescue Errno::EPIPE
    nil
  end

  def kill
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
  end

  def retire
    shutdown
    busy, wall = drain_stats
    close_pipes
    reap
    @busy_time = busy
    @wall_time = wall
    to_stat
  end

  def to_stat
    Evilution::Parallel::WorkQueue::WorkerStat.new(
      @pid, @items_completed, @busy_time || 0.0, @wall_time || 0.0
    )
  end

  private

  def drain_stats
    return [0.0, 0.0] unless @res_read.wait_readable(Evilution::Parallel::WorkQueue::TIMING_GRACE_PERIOD)

    message = read_result
    return [0.0, 0.0] if message.nil?

    tag, busy, wall = message
    return [0.0, 0.0] unless tag == Evilution::Parallel::WorkQueue::STATS

    [busy, wall]
  end
end
