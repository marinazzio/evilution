# frozen_string_literal: true

module Evilution
  module Mutator
    class Registry
      def initialize
        @operators = []
      end

      def register(operator_class)
        @operators << operator_class
        self
      end

      def mutations_for(subject)
        @operators.flat_map do |operator_class|
          operator_class.new.call(subject)
        end
      end

      def operator_count
        @operators.length
      end

      def operators
        @operators.dup
      end
    end
  end
end
