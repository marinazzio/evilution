# frozen_string_literal: true

require_relative "../parallel"

class Evilution::Parallel::WorkQueue
  SHUTDOWN = :__shutdown__

  STATS = :__stats__

  TIMING_GRACE_PERIOD = 5

  WorkerStat = Struct.new(:pid, :items_completed, :busy_time, :wall_time) do
    def idle_time
      wall_time - busy_time
    end

    def utilization
      return 0.0 if wall_time.nil? || wall_time.zero?

      busy_time / wall_time
    end
  end

  def initialize(size:, hooks: nil, prefetch: 1, item_timeout: nil)
    raise ArgumentError, "pool size must be a positive integer, got #{size.inspect}" unless size.is_a?(Integer) && size >= 1
    raise ArgumentError, "prefetch must be a positive integer, got #{prefetch.inspect}" unless prefetch.is_a?(Integer) && prefetch >= 1
    unless item_timeout.nil? || (item_timeout.is_a?(Numeric) && item_timeout.positive?)
      raise ArgumentError, "item_timeout must be nil or a positive number, got #{item_timeout.inspect}"
    end

    @size = size
    @hooks = hooks
    @prefetch = prefetch
    @item_timeout = item_timeout
    @worker_stats = []
  end

  def map(items, &)
    return [] if items.empty?

    worker_count = [@size, items.length].min
    workers = spawn_workers(worker_count, &)

    begin
      distribute_and_collect(items, workers)
    ensure
      shutdown_workers(workers)
      @worker_stats = build_worker_stats(workers)
    end
  end

  def worker_stats
    @worker_stats.map { |stat| stat.dup.freeze }
  end

  private

  def spawn_workers(count, &)
    count.times.map do
      cmd_read, cmd_write = IO.pipe
      res_read, res_write = IO.pipe

      pid = Process.fork do
        cmd_write.close
        res_read.close
        worker_loop(cmd_read, res_write, &)
      end

      cmd_read.close
      res_write.close

      { pid: pid, cmd_write: cmd_write, res_read: res_read, items_completed: 0, pending: 0 }
    end
  end

  def worker_loop(cmd_read, res_write, &block)
    @hooks.fire(:worker_process_start) if @hooks
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    busy_time = 0.0

    loop do
      data = read_command(cmd_read)
      break if data == SHUTDOWN

      index, item = data
      begin
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = block.call(item)
        busy_time += Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
        write_message(res_write, [index, :ok, result])
      rescue Exception => e # rubocop:disable Lint/RescueException
        busy_time += Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
        write_message(res_write, [index, :error, e])
      end
    end

    wall_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    write_message(res_write, [STATS, busy_time, wall_time])
  ensure
    cmd_read.close
    res_write.close
    exit!
  end

  def distribute_and_collect(items, workers)
    state = CollectionState.new(items.length)
    seed_workers(items, workers, state)
    collect_results(items, workers, state)
    raise state.first_error if state.first_error

    state.results
  end

  def seed_workers(items, workers, state)
    @prefetch.times do
      workers.each do |worker|
        break unless state.next_index < items.length

        send_item(worker, items, state)
      end
    end
  end

  def collect_results(items, workers, state)
    io_to_worker = workers.to_h { |w| [w[:res_read], w] }
    result_ios = io_to_worker.keys

    while state.in_flight.positive?
      readable, = IO.select(result_ios, nil, nil, @item_timeout)

      if readable.nil?
        terminate_stuck_workers(workers)
        state.first_error = Evilution::Error.new("worker timed out after #{@item_timeout}s") if state.first_error.nil?
        break
      end

      readable.each do |io|
        alive = handle_result(io, io_to_worker[io], items, state)
        result_ios.delete(io) unless alive
      end
    end
  end

  def handle_result(io, worker, items, state)
    message = read_result(io)

    if message.nil?
      state.first_error = Evilution::Error.new("worker process exited unexpectedly") if state.first_error.nil?
      state.in_flight -= worker[:pending]
      worker[:pending] = 0
      return false
    end

    index, status, value = message
    state.first_error = value if status == :error && state.first_error.nil?
    state.results[index] = value if status == :ok
    state.in_flight -= 1
    worker[:pending] -= 1
    worker[:items_completed] += 1

    send_item(worker, items, state) if state.next_index < items.length && state.first_error.nil?
    true
  end

  def send_item(worker, items, state)
    write_message(worker[:cmd_write], [state.next_index, items[state.next_index]])
    state.next_index += 1
    state.in_flight += 1
    worker[:pending] += 1
  end

  def build_worker_stats(workers)
    workers.map do |worker|
      WorkerStat.new(worker[:pid], worker[:items_completed], worker[:busy_time] || 0.0, worker[:wall_time] || 0.0)
    end
  end

  def terminate_stuck_workers(workers)
    workers.each do |worker|
      Process.kill("KILL", worker[:pid])
    rescue Errno::ESRCH
      nil # Already exited
    end
  end

  def shutdown_workers(workers)
    workers.each do |worker|
      write_message(worker[:cmd_write], SHUTDOWN)
    rescue Errno::EPIPE
      # Worker already exited
    end

    collect_worker_timing(workers)

    workers.each do |worker|
      worker[:cmd_write].close unless worker[:cmd_write].closed?
      worker[:res_read].close unless worker[:res_read].closed?
      Process.wait(worker[:pid])
    rescue Errno::ECHILD
      # Already reaped
    end
  end

  def collect_worker_timing(workers)
    io_to_worker = workers.reject { |w| w[:res_read].closed? }.to_h { |w| [w[:res_read], w] }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMING_GRACE_PERIOD

    until io_to_worker.empty?
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break if remaining <= 0

      readable, = IO.select(io_to_worker.keys, nil, nil, remaining)
      break unless readable

      readable.each { |io| apply_worker_timing(io_to_worker.delete(io), io) }
    end
  end

  def apply_worker_timing(worker, io)
    message = read_result(io)
    return if message.nil?

    tag, busy_time, wall_time = message
    return unless tag == STATS

    worker[:busy_time] = busy_time
    worker[:wall_time] = wall_time
  end

  def write_message(io, data)
    payload = Marshal.dump(data)
    io.write([payload.bytesize].pack("N"))
    io.write(payload)
    io.flush
  end

  def read_command(io)
    header = io.read(4)
    return SHUTDOWN if header.nil? || header.bytesize < 4

    length = header.unpack1("N")
    payload = io.read(length)
    return SHUTDOWN if payload.nil? || payload.bytesize < length

    Marshal.load(payload) # rubocop:disable Security/MarshalLoad
  end

  def read_result(io)
    header = io.read(4)
    return nil if header.nil? || header.bytesize < 4

    length = header.unpack1("N")
    payload = io.read(length)
    return nil if payload.nil? || payload.bytesize < length

    Marshal.load(payload) # rubocop:disable Security/MarshalLoad
  end

  CollectionState = Struct.new(:results, :in_flight, :next_index, :first_error) do
    def initialize(item_count)
      super(Array.new(item_count), 0, 0, nil)
    end
  end
  private_constant :CollectionState
end
