class ConditionalFlipExample
  def simple_if(x)
    if x > 0
      "positive"
    end
  end

  def simple_unless(x)
    unless x > 0
      "non-positive"
    end
  end

  def if_else(x)
    if x > 0
      "positive"
    else
      "non-positive"
    end
  end

  def unless_else(x)
    unless x > 0
      "non-positive"
    else
      "positive"
    end
  end

  def modifier_if(x)
    return "positive" if x > 0
  end

  def modifier_unless(x)
    return "non-positive" unless x > 0
  end

  def ternary(x)
    x > 0 ? "positive" : "non-positive"
  end

  def with_elsif(x)
    if x > 0
      "positive"
    elsif x == 0
      "zero"
    else
      "negative"
    end
  end
end
