# frozen_string_literal: true

require "timeout"
require "stringio"
require_relative "../result/mutation_result"

module Evilution
  module Isolation
    class InProcess
      def call(mutation:, test_command:, timeout:)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = execute_with_timeout(mutation, test_command, timeout)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

        build_mutation_result(mutation, result, duration)
      end

      private

      def execute_with_timeout(mutation, test_command, timeout)
        saved_features = $LOADED_FEATURES.dup
        result = Timeout.timeout(timeout) do
          suppress_output { test_command.call(mutation) }
        end
        { timeout: false }.merge(result)
      rescue Timeout::Error
        { timeout: true }
      rescue StandardError => e
        { timeout: false, passed: false, error: e.message }
      ensure
        cleanup_loaded_features(saved_features)
      end

      def suppress_output
        saved_stdout = $stdout
        saved_stderr = $stderr
        $stdout = StringIO.new
        $stderr = StringIO.new
        yield
      ensure
        $stdout = saved_stdout
        $stderr = saved_stderr
      end

      def cleanup_loaded_features(saved_features)
        added = $LOADED_FEATURES - saved_features
        added.each { |f| $LOADED_FEATURES.delete(f) }
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
          duration: duration,
          test_command: result[:test_command]
        )
      end
    end
  end
end
