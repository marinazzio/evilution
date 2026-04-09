class RegexSimplificationExample
  def with_plus_quantifier(str)
    str.match?(/\d+/)
  end

  def with_star_quantifier(str)
    str.match?(/\s*/)
  end

  def with_question_quantifier(str)
    str.match?(/\d?/)
  end

  def with_curly_quantifier(str)
    str.match?(/\d{2,4}/)
  end

  def with_anchors(str)
    str.match?(/^foo$/)
  end

  def with_backslash_anchors(str)
    str.match?(/\Afoo\z/)
  end

  def with_character_class_range(str)
    str.match?(/[a-z]/)
  end

  def with_multiple_ranges(str)
    str.match?(/[a-zA-Z0-9]/)
  end

  def with_combined(str)
    str.match?(/^\d+[a-z]*$/)
  end

  def no_regexp(str)
    str.upcase
  end

  def with_empty_regexp(str)
    str.match?(//)
  end

  def with_escaped_quantifier(str)
    str.match?(/\d\+/)
  end
end
