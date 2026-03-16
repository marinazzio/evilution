# frozen_string_literal: true

module Evilution
  module Parallel
    class Pool
      def initialize(size:)
        @size = size
      end

      def map(items, &block)
        results = []

        items.each_slice(@size) do |batch|
          threads = batch.map do |item|
            Thread.new { block.call(item) }
          end
          results.concat(threads.map(&:value))
        end

        results
      end
    end
  end
end
