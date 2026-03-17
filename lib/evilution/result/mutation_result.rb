# frozen_string_literal: true

module Evilution
  module Result
    class MutationResult
      STATUSES = %i[killed survived timeout error neutral].freeze

      attr_reader :mutation, :status, :duration, :killing_test, :test_command

      def initialize(mutation:, status:, duration: 0.0, killing_test: nil, test_command: nil)
        raise ArgumentError, "invalid status: #{status}" unless STATUSES.include?(status)

        @mutation = mutation
        @status = status
        @duration = duration
        @killing_test = killing_test
        @test_command = test_command
        freeze
      end

      def killed?
        status == :killed
      end

      def survived?
        status == :survived
      end

      def timeout?
        status == :timeout
      end

      def error?
        status == :error
      end

      def neutral?
        status == :neutral
      end
    end
  end
end
