class AgeChecker
  def adult?(age)
    age >= 18
  end

  def teenager?(age)
    age > 12 && age < 20
  end

  def equal_check(a, b)
    a == b
  end

  def not_equal_check(a, b)
    a != b
  end

  def at_most?(value, limit)
    value <= limit
  end
end
