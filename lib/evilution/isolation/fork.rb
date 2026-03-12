# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Evilution
  module Isolation
    class Fork
      TEMP_DIR_PATTERN = "evilution*"
      GRACE_PERIOD = 2

      def call(mutation:, test_command:, timeout:)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        read_io, write_io = IO.pipe
        existing_temp_dirs = Dir.glob(File.join(Dir.tmpdir, TEMP_DIR_PATTERN))

        pid = ::Process.fork do
          read_io.close
          result = execute_in_child(mutation, test_command)
          Marshal.dump(result, write_io)
          write_io.close
          exit!(result[:passed] ? 0 : 1)
        end

        write_io.close
        result = wait_for_result(pid, read_io, timeout)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        build_mutation_result(mutation, result, duration)
      ensure
        read_io&.close
        write_io&.close
        restore_original_source(mutation)
        cleanup_leaked_temp_dirs(existing_temp_dirs)
      end

      private

      def restore_original_source(mutation)
        return if File.read(mutation.file_path) == mutation.original_source

        File.write(mutation.file_path, mutation.original_source)
      rescue StandardError => e
        warn("Warning: failed to restore #{mutation.file_path}: #{e.message}")
      end

      def cleanup_leaked_temp_dirs(existing_temp_dirs)
        current_temp_dirs = Dir.glob(File.join(Dir.tmpdir, TEMP_DIR_PATTERN))
        leaked = current_temp_dirs - existing_temp_dirs
        leaked.each { |dir| FileUtils.rm_rf(dir) }
      rescue StandardError => e
        warn("Warning: failed to clean up temp directories: #{e.message}")
      end

      def execute_in_child(mutation, test_command)
        test_command.call(mutation)
      rescue StandardError => e
        { passed: false, error: e.message }
      end

      def wait_for_result(pid, read_io, timeout)
        if read_io.wait_readable(timeout)
          data = read_io.read
          ::Process.wait(pid)
          return { timeout: false }.merge(Marshal.load(data)) unless data.empty? # rubocop:disable Security/MarshalLoad

          ::Process.wait(pid) rescue nil # rubocop:disable Style/RescueModifier
          { timeout: false, passed: false, error: "empty result from child" }
        else
          terminate_child(pid)
          { timeout: true }
        end
      end

      def terminate_child(pid)
        ::Process.kill("TERM", pid) rescue nil # rubocop:disable Style/RescueModifier
        _, status = ::Process.waitpid2(pid, ::Process::WNOHANG)
        return if status

        sleep(GRACE_PERIOD)
        _, status = ::Process.waitpid2(pid, ::Process::WNOHANG)
        return if status

        ::Process.kill("KILL", pid) rescue nil # rubocop:disable Style/RescueModifier
        ::Process.wait(pid) rescue nil # rubocop:disable Style/RescueModifier
      end

      def build_mutation_result(mutation, result, duration)
        status = if result[:timeout]
                   :timeout
                 elsif result[:error]
                   :error
                 elsif result[:passed]
                   :survived
                 else
                   :killed
                 end

        Result::MutationResult.new(
          mutation: mutation,
          status: status,
          duration: duration
        )
      end
    end
  end
end
