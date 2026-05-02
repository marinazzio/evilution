# frozen_string_literal: true

require_relative "../diff_extractor"

# Extracts {minus:, plus:} payload arrays from Mutant unified-diff format.
# Strips the "---", "+++", and "@@" header/hunk lines and preserves a single
# leading "-" / "+" character without a trailing space (mutant style).
class Evilution::Compare::DiffExtractor::Mutant
  def call(diff)
    minus = []
    plus = []
    diff.to_s.each_line do |line|
      line = line.chomp
      next if line.start_with?("---", "+++", "@@")

      if line.start_with?("-")
        minus << line[1..]
      elsif line.start_with?("+")
        plus << line[1..]
      end
    end
    { minus: minus, plus: plus }
  end
end
