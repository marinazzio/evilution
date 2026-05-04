class ConditionalChecker
  def with_else(x)
    if x > 0
      x * 2
    else
      x * -1
    end
  end

  def without_else(x)
    if x > 0
      x * 2
    end
  end

  def with_elsif(x)
    if x > 0
      x * 2
    elsif x < 0
      x * -1
    else
      0
    end
  end
end
