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
end
