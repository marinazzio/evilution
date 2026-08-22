class BooleanToNilTarget
  def both_true?(a, b)
    a && b
  end

  def either_true?(a, b)
    a || b
  end

  def word_and?(a, b)
    a and b
  end

  def word_or?(a, b)
    a or b
  end

  def guarded(a, b)
    return 0 if a && b

    1
  end

  def nested(a, b, c)
    a && (b || c)
  end

  def or_nested(a, b, c)
    a || (b && c)
  end
end
