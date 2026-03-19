class RangeReplacementExample
  def inclusive(a, b)
    (a..b).to_a
  end

  def exclusive(a, b)
    (a...b).to_a
  end

  def in_case(x)
    case x
    when 1..10
      "low"
    when 11...20
      "high"
    end
  end

  def no_range(x)
    x + 1
  end
end
