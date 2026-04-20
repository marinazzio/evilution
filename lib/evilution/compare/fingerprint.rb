# frozen_string_literal: true

require "digest"
require_relative "../compare"

module Evilution::Compare::Fingerprint
  module_function

  def extract_from_evilution_diff(diff)
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

  def extract_from_mutant_diff(diff)
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

  # v1 limitation: only " and ' literals are preserved. Regex literals (/.../),
  # heredocs, %w[], %q{} forms are treated as ordinary code — whitespace runs
  # inside them collapse. A mutation touching whitespace inside a regex may
  # false-match across tools.
  # rubocop:disable Metrics/PerceivedComplexity, Style/MultipleComparison
  def normalize_line(line)
    out = +""
    i = 0
    in_literal = nil
    last_was_space = false
    chars = line.chars
    while i < chars.length
      ch = chars[i]
      if in_literal
        out << ch
        if ch == "\\" && i + 1 < chars.length
          out << chars[i + 1]
          i += 2
          next
        end
        in_literal = nil if ch == in_literal
      elsif ch == '"' || ch == "'"
        in_literal = ch
        out << ch
        last_was_space = false
      elsif ch == " " || ch == "\t"
        out << " " unless last_was_space || out.empty?
        last_was_space = true
      else
        out << ch
        last_was_space = false
      end
      i += 1
    end
    out.rstrip
  end
  # rubocop:enable Metrics/PerceivedComplexity, Style/MultipleComparison

  def compute(file_path:, line:, body:)
    minus = body[:minus].map { |l| normalize_line(l) }
    plus  = body[:plus].map  { |l| normalize_line(l) }
    payload = [file_path, line.to_s, minus.join("\n"), plus.join("\n")].join("\x00")
    Digest::SHA256.hexdigest(payload)
  end
end
