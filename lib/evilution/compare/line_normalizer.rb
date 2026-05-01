# frozen_string_literal: true

require_relative "../compare"

# Collapses whitespace runs in source-code text while preserving the contents
# of "..." and '...' string literals. Used for fingerprinting mutation diffs
# so that whitespace-only differences do not cause false fingerprint mismatches
# across tooling (evilution vs mutant).
#
# v1 limitation: only " and ' literals are preserved. Regex literals (/.../),
# heredocs, %w[], %q{} forms are treated as ordinary code — whitespace runs
# inside them collapse. A mutation touching whitespace inside a regex may
# false-match across tools.
class Evilution::Compare::LineNormalizer
  QUOTES = ['"', "'"].freeze
  WHITESPACE = [" ", "\t"].freeze
  private_constant :QUOTES, :WHITESPACE

  def call(line)
    @chars = line.chars
    @i = 0
    @out = +""
    @in_literal = nil
    @last_was_space = false

    @i += step while @i < @chars.length
    @out.rstrip
  end

  private

  def step
    ch = @chars[@i]
    return step_in_literal(ch) if @in_literal
    return step_open_quote(ch) if QUOTES.include?(ch)
    return step_whitespace if WHITESPACE.include?(ch)

    append_regular(ch)
  end

  def step_in_literal(ch)
    @out << ch
    if ch == "\\" && @i + 1 < @chars.length
      @out << @chars[@i + 1]
      return 2
    end
    @in_literal = nil if ch == @in_literal
    1
  end

  def step_open_quote(ch)
    @in_literal = ch
    @out << ch
    @last_was_space = false
    1
  end

  def step_whitespace
    @out << " " unless @last_was_space || @out.empty?
    @last_was_space = true
    1
  end

  def append_regular(ch)
    @out << ch
    @last_was_space = false
    1
  end
end
