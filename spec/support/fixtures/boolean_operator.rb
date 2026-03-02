class BooleanChecker
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
end
