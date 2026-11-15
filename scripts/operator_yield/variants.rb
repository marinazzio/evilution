# frozen_string_literal: true

# Names the variant of a literal operator's mutation from its diff, so a study
# can look at (and drop) e.g. only the `nil` replacement of integer_literal.
# The changed text is the diff's first -/+ pair with the common prefix and
# suffix stripped, widened to whole tokens.
module Variants
  # Replacements IntegerLiteral emits for crossing an integer width; kept in
  # step with Evilution::Mutator::Operator::IntegerLiteral::WIDTH_SENTINELS.
  WIDTH_SENTINELS = [167, 467, 55_487, 108_503, 2_667_278_543, 7_980_081_959, 15_508_464_536_481_899_903].freeze

  module_function

  def of(operator, diff)
    from, to = change_of(diff)
    case operator
    when "integer_literal" then integer_variant(from, to)
    when "float_literal" then float_variant(to)
    when "string_literal" then string_variant(to)
    when "array_literal", "hash_literal" then collection_variant(from, to)
    else other_variant(to)
    end
  end

  def change_of(diff)
    minus = side(diff, "-")
    plus = side(diff, "+")
    pre, suf = token_bounds(minus, plus)
    [minus[pre...(minus.size - suf)], plus[pre...(plus.size - suf)]]
  end

  # Common prefix and suffix lengths, widened to whole tokens so 10 -> 11
  # reads as "10" -> "11", not "0" -> "1".
  def token_bounds(minus, plus)
    pre = common_prefix(minus, plus)
    suf = common_suffix(minus, plus, pre)
    pre -= 1 while pre.positive? && minus[pre - 1].match?(/[\w.]/)
    suf -= 1 while suf.positive? && minus[minus.size - suf].match?(/\w/)
    [pre, suf]
  end

  def side(diff, sign)
    diff.lines.find { |l| l.start_with?(sign) }.to_s.delete_prefix(sign).chomp
  end

  def common_prefix(a, b)
    n = 0
    n += 1 while n < a.size && n < b.size && a[n] == b[n]
    n
  end

  def common_suffix(a, b, pre)
    n = 0
    n += 1 while n < a.size - pre && n < b.size - pre && a[-1 - n] == b[-1 - n]
    n
  end

  def integer_token(str)
    m = str.match(/(-?[0-9][0-9_]*)\z/) || str.match(/\A(-?[0-9][0-9_]*)/)
    m && Integer(m[1].delete("_"), 10)
  rescue ArgumentError
    nil
  end

  # The width sentinel is classified before the neighbours: a 0 literal gets
  # 1, -1 and the sentinel 167, and the sentinel is not a step from zero.
  def integer_variant(from, to)
    return "nil" if to.end_with?("nil")

    a = integer_token(from)
    b = integer_token(to)
    return "?" unless a && b
    return "width_sentinel" if WIDTH_SENTINELS.include?(b) && (b - a).abs > 1

    integer_step(a, b)
  end

  def integer_step(a, b)
    return "zero" if b.zero? && !a.zero?
    return "from_zero(+1/-1)" if a.zero?
    return "succ" if b == a + 1
    return "pred" if b == a - 1

    "other"
  end

  def float_variant(to)
    return "nan" if to.include?("NAN")
    return "infinity" if to.include?("INFINITY")
    return "nil" if to.include?("nil")
    return "zero" if to.match?(/\b0\.0\z/)

    "other(#{to[0, 12]})"
  end

  def string_variant(to)
    return "nil" if to.end_with?("nil")
    return "empty" if to.end_with?('""', "''")

    "other"
  end

  def collection_variant(from, to)
    return "empty" if to.match?(/\[\]|\{\}/) && from.size > 2
    return "nil" if to.include?("nil")

    "delete_each/other"
  end

  def other_variant(to)
    stripped = to.strip
    return "removed" if stripped.empty?

    stripped.size <= 12 ? stripped : "other"
  end
end
