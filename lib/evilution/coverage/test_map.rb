# frozen_string_literal: true

module Evilution
  module Coverage
    class TestMap
      def initialize(coverage_data)
        @coverage_data = coverage_data
      end

      # Returns true if the given source line was executed during tests.
      # file_path should be an absolute path matching coverage data keys.
      # line is 1-based (editor line numbers).
      def covered?(file_path, line)
        line_data = @coverage_data[file_path]
        return false unless line_data

        index = line - 1
        return false if index.negative? || index >= line_data.length

        count = line_data[index]
        !count.nil? && count.positive?
      end
    end
  end
end
