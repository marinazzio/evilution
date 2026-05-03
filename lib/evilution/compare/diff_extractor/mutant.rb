# frozen_string_literal: true

require_relative "../diff_extractor"

# Extracts {minus:, plus:} payload arrays from Mutant unified-diff format.
# Skips the "--- <name>", "+++ <name>", and "@@ ... @@" header lines and
# returns each remaining payload line with its single leading "-" or "+"
# marker stripped.
#
# Header detection requires a trailing space after "---"/"+++" so that a
# payload line whose mutated source starts with "--" (emitted as "---var")
# or "++" (emitted as "+++var") is preserved rather than misclassified as
# a header.
class Evilution::Compare::DiffExtractor::Mutant
  def call(diff)
    minus = []
    plus = []
    diff.to_s.each_line do |line|
      line = line.chomp
      next if line.start_with?("--- ", "+++ ", "@@")

      if line.start_with?("-")
        minus << line[1..]
      elsif line.start_with?("+")
        plus << line[1..]
      end
    end
    { minus: minus, plus: plus }
  end
end
