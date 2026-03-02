# frozen_string_literal: true

module Evilution
  module AST
    module SourceSurgeon
      def self.apply(source, offset:, length:, replacement:)
        result = source.dup
        result[offset, length] = replacement
        result
      end
    end
  end
end
