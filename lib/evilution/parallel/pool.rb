# frozen_string_literal: true

module Evilution
  module Parallel
    class Pool
      def initialize(jobs:)
        @jobs = jobs
      end

      # Executes mutations in parallel across N worker processes.
      #
      # @param mutations [Array] Array of mutation objects to run
      # @param test_command_builder [#call] Callable that receives a mutation and returns a test command callable
      # @param timeout [Numeric] Per-mutation timeout in seconds
      # @return [Array<Result::MutationResult>]
      def call(mutations:, test_command_builder:, timeout:)
        return [] if mutations.empty?

        worker_count = [@jobs, mutations.size].min
        chunks = partition(mutations, worker_count)

        pipes = worker_count.times.map { IO.pipe }

        pids = chunks.each_with_index.map do |chunk, index|
          _, write_io = pipes[index]

          pid = Process.fork do
            # Close all read ends in the child; close sibling write ends too
            pipes.each_with_index do |(r, w), i|
              if i == index
                r.close
              else
                r.close
                w.close
              end
            end

            results = run_chunk(chunk, test_command_builder, timeout)
            Marshal.dump(results, write_io)
            write_io.close
            exit!(0)
          end

          write_io.close
          pid
        end

        results = collect_results(pipes.map(&:first), pids)

        results
      ensure
        # Ensure all pipes are closed even if something goes wrong
        pipes&.each do |read_io, write_io|
          read_io.close unless read_io.closed?
          write_io.close unless write_io.closed?
        end
      end

      private

      attr_reader :jobs

      # Divides mutations into N chunks, grouping by file path so no two
      # workers mutate the same file simultaneously (which would corrupt it).
      def partition(mutations, n)
        by_file = mutations.group_by(&:file_path)
        chunks = Array.new(n) { [] }

        # Assign each file's mutations to the least-loaded chunk
        by_file.values.sort_by { |group| -group.size }.each do |group|
          smallest = chunks.min_by(&:size)
          smallest.concat(group)
        end

        chunks
      end

      # Runs a chunk of mutations sequentially inside a worker process.
      def run_chunk(mutations, test_command_builder, timeout)
        worker = Worker.new
        worker.call(mutations: mutations, test_command_builder: test_command_builder, timeout: timeout)
      end

      # Reads results from all worker pipes and waits for workers to finish.
      def collect_results(read_ios, pids)
        results = []

        read_ios.each_with_index do |read_io, _index|
          data = read_io.read
          read_io.close

          unless data.empty?
            chunk_results = Marshal.load(data) # rubocop:disable Security/MarshalLoad
            results.concat(chunk_results)
          end
        end

        pids.each { |pid| Process.wait(pid) rescue nil } # rubocop:disable Style/RescueModifier

        results
      end
    end
  end
end
