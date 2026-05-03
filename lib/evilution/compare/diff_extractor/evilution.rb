# frozen_string_literal: true

require_relative "../diff_extractor"

# Extracts {minus:, plus:} payload arrays from Evilution-format diffs.
# Evilution diffs use "- " / "+ " line prefixes (note the trailing space) and
# do not carry unified-diff headers or hunk markers.
class Evilution::Compare::DiffExtractor::Evilution
  def call(diff)
    minus = []
    plus = []
    diff.to_s.each_line do |line|
      line = line.chomp
      if line.start_with?("- ")
        minus << line[2..]
      elsif line.start_with?("+ ")
        plus << line[2..]
      end
    end
    { minus: minus, plus: plus }
  end
end
