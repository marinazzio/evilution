# frozen_string_literal: true

require_relative "../suggestion"

class Evilution::Reporter::Suggestion::DiffLines
  def self.from_diff(raw_diff)
    lines = raw_diff.split("\n")
    new(
      original: clean(lines.find { |l| l.start_with?("- ") }, "- "),
      mutated: clean(lines.find { |l| l.start_with?("+ ") }, "+ ")
    )
  end

  def self.clean(line, prefix)
    return nil if line.nil?

    line.sub(/^#{Regexp.escape(prefix)}/, "").strip
  end
  private_class_method :clean

  attr_reader :original, :mutated

  def initialize(original:, mutated:)
    @original = original
    @mutated = mutated
    freeze
  end
end
