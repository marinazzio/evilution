# frozen_string_literal: true

require_relative "../parallel"

class Evilution::Parallel::Pool
  def initialize(size:, hooks: nil)
    raise ArgumentError, "pool size must be a positive integer, got #{size.inspect}" unless size.is_a?(Integer) && size >= 1

    @size = size
    @hooks = hooks
  end

  def map(items, &block)
    results = []

    items.each_slice(@size) do |batch|
      results.concat(run_batch(batch, &block))
    end

    results
  end

  private

  def run_batch(items, &block)
    entries = items.map do |item|
      read_io, write_io = IO.pipe
      pid = fork_worker(item, read_io, write_io, &block)
      write_io.close
      { pid: pid, read_io: read_io }
    end

    collect_results(entries)
  end

  def fork_worker(item, read_io, write_io, &block)
    Process.fork do
      read_io.close
      @hooks&.fire(:worker_process_start)
      result = block.call(item)
      Marshal.dump(result, write_io)
    rescue Exception => e # rubocop:disable Lint/RescueException
      Marshal.dump(e, write_io)
    ensure
      write_io.close
      exit!
    end
  end

  def collect_results(entries)
    entries.map do |entry|
      data = entry[:read_io].read
      entry[:read_io].close
      Process.wait(entry[:pid])
      raise Evilution::Error, "worker process failed with no result" if data.empty?

      result = Marshal.load(data) # rubocop:disable Security/MarshalLoad
      raise result if result.is_a?(Exception)

      result
    end
  end
end
