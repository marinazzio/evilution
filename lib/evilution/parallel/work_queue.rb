# frozen_string_literal: true

require_relative "../parallel"

class Evilution::Parallel::WorkQueue
  SHUTDOWN = :__shutdown__

  def initialize(size:, hooks: nil)
    raise ArgumentError, "pool size must be a positive integer, got #{size.inspect}" unless size.is_a?(Integer) && size >= 1

    @size = size
    @hooks = hooks
  end

  def map(items, &)
    return [] if items.empty?

    worker_count = [@size, items.length].min
    workers = spawn_workers(worker_count, &)

    begin
      distribute_and_collect(items, workers)
    ensure
      shutdown_workers(workers)
    end
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

      { pid: pid, cmd_write: cmd_write, res_read: res_read }
    end
  end

  def worker_loop(cmd_read, res_write, &block)
    @hooks.fire(:worker_process_start) if @hooks

    loop do
      data = read_command(cmd_read)
      break if data == SHUTDOWN

      index, item = data
      begin
        result = block.call(item)
        write_message(res_write, [index, :ok, result])
      rescue Exception => e # rubocop:disable Lint/RescueException
        write_message(res_write, [index, :error, e])
      end
    end
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
    workers.each do |worker|
      break unless state.next_index < items.length

      send_item(worker, items, state)
    end
  end

  def collect_results(items, workers, state)
    io_to_worker = workers.to_h { |w| [w[:res_read], w] }
    result_ios = io_to_worker.keys

    while state.in_flight.positive?
      readable, = IO.select(result_ios)
      readable.each { |io| handle_result(io, io_to_worker[io], items, state) }
    end
  end

  def handle_result(io, worker, items, state)
    message = read_result(io)

    if message.nil?
      state.first_error = Evilution::Error.new("worker process exited unexpectedly") if state.first_error.nil?
      state.in_flight -= 1
      return
    end

    index, status, value = message
    state.first_error = value if status == :error && state.first_error.nil?
    state.results[index] = value if status == :ok
    state.in_flight -= 1

    send_item(worker, items, state) if state.next_index < items.length && state.first_error.nil?
  end

  def send_item(worker, items, state)
    write_message(worker[:cmd_write], [state.next_index, items[state.next_index]])
    state.next_index += 1
    state.in_flight += 1
  end

  def shutdown_workers(workers)
    workers.each do |worker|
      write_message(worker[:cmd_write], SHUTDOWN)
    rescue Errno::EPIPE
      # Worker already exited
    end

    workers.each do |worker| # rubocop:disable Style/CombinableLoops
      worker[:cmd_write].close unless worker[:cmd_write].closed?
      worker[:res_read].close unless worker[:res_read].closed?
      Process.wait(worker[:pid])
    rescue Errno::ECHILD
      # Already reaped
    end
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
