# frozen_string_literal: true

module Evilution
  module Diff
    class Parser
      # Parses git diff output to extract changed file paths and line ranges.
      #
      # @param diff_base [String] Git ref to diff against (e.g., "HEAD~1", "main")
      # @return [Array<Hash>] Array of { file: String, lines: Array<Range> }
      def parse(diff_base)
        output = run_git_diff(diff_base)
        parse_diff_output(output)
      end

      private

      def run_git_diff(diff_base)
        `git diff --unified=0 #{diff_base}..HEAD -- '*.rb' 2>/dev/null`
      end

      def parse_diff_output(output)
        result = {}
        current_file = nil

        output.each_line do |line|
          case line
          when %r{^diff --git a/.+ b/(.+)$}
            current_file = Regexp.last_match(1)
          when /^@@\s+-\d+(?:,\d+)?\s+\+(\d+)(?:,(\d+))?\s+@@/
            next unless current_file

            start_line = Regexp.last_match(1).to_i
            count = (Regexp.last_match(2) || "1").to_i

            next if count.zero? # Pure deletion, no new lines

            end_line = start_line + count - 1
            result[current_file] ||= []
            result[current_file] << (start_line..end_line)
          end
        end

        result.map { |file, lines| { file: file, lines: lines } }
      end
    end
  end
end
