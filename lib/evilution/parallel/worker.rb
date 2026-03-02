# frozen_string_literal: true

module Evilution
  module Parallel
    class Worker
      def initialize(isolator: Isolation::Fork.new)
        @isolator = isolator
      end

      # Runs a batch of mutations sequentially using fork isolation.
      #
      # @param mutations [Array<Mutation>] Mutations to execute
      # @param test_command_builder [#call] Receives a mutation, returns a test command callable
      # @param timeout [Numeric] Per-mutation timeout in seconds
      # @return [Array<Result::MutationResult>]
      def call(mutations:, test_command_builder:, timeout:)
        mutations.map do |mutation|
          test_command = test_command_builder.call(mutation)
          @isolator.call(mutation: mutation, test_command: test_command, timeout: timeout)
        end
      end
    end
  end
end
