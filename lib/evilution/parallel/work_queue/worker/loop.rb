# frozen_string_literal: true

require_relative "../worker"
require_relative "../channel"
require_relative "../channel/frame"

module Evilution::Parallel::WorkQueue::Worker::Loop
  module_function

  def run(cmd_io, res_io, hooks: nil, &block)
    hooks.fire(:worker_process_start) if hooks
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    busy = 0.0

    loop do
      data = Evilution::Parallel::WorkQueue::Channel.read(cmd_io)
      break if data.nil? || data == Evilution::Parallel::WorkQueue::SHUTDOWN

      busy += run_one(res_io, data, &block)
    end

    wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    Evilution::Parallel::WorkQueue::Channel.write(
      res_io, [Evilution::Parallel::WorkQueue::STATS, busy, wall]
    )
  ensure
    cmd_io.close unless cmd_io.closed?
    res_io.close unless res_io.closed?
    exit!
  end

  def run_one(res_io, data, &block)
    index, item = data
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      result = block.call(item)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      Evilution::Parallel::WorkQueue::Channel.write(res_io, [index, :ok, result])
    rescue Exception => e # rubocop:disable Lint/RescueException
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      Evilution::Parallel::WorkQueue::Channel.write(res_io, [index, :error, e])
    end
    elapsed
  end
end
