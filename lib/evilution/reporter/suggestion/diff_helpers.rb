# frozen_string_literal: true

require_relative "../suggestion"

module Evilution::Reporter::Suggestion::DiffHelpers
  module_function

  def parse_method_name(subject_name)
    subject_name.split(/[#.]/).last
  end

  def sanitize_method_name(name)
    name.gsub(/[^a-zA-Z0-9_]/, "_").gsub(/_+/, "_").gsub(/\A_|_\z/, "")
  end

  def extract_diff_lines(diff)
    lines = diff.split("\n")
    original = lines.find { |l| l.start_with?("- ") }
    mutated = lines.find { |l| l.start_with?("+ ") }
    [clean_diff_line(original, "- "), clean_diff_line(mutated, "+ ")]
  end

  def clean_diff_line(line, prefix)
    return nil if line.nil?

    line.sub(/^#{Regexp.escape(prefix)}/, "").strip
  end
end
