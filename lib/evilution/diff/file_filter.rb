# frozen_string_literal: true

module Evilution
  module Diff
    class FileFilter
      # Filters subjects to only those whose methods overlap with changed lines.
      #
      # @param subjects [Array<Subject>] All extracted subjects
      # @param changed_ranges [Array<Hash>] Output from Diff::Parser#parse
      # @return [Array<Subject>] Subjects overlapping with changes
      def filter(subjects, changed_ranges)
        lookup = build_lookup(changed_ranges)

        subjects.select do |subject|
          ranges = lookup[subject.file_path]
          next false unless ranges

          ranges.any? { |range| range.cover?(subject.line_number) }
        end
      end

      private

      def build_lookup(changed_ranges)
        changed_ranges.to_h { [_1[:file], _1[:lines]] }
      end
    end
  end
end
