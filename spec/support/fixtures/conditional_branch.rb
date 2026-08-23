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

  def unless_with_else(x)
    unless x > 0
      x * 2
    else
      x * -1
    end
  end

  def unless_without_else(x)
    unless x > 0
      x * 2
    end
  end

  def unless_with_empty_else(x)
    unless x > 0
      x * 2
    else
    end
  end

  def unless_modifier(x)
    x * 2 unless x > 0
  end

  def unless_nested_in_unless(x)
    unless x > 10
      unless x > 20
        x * 2
      end
    end
  end

  def unless_nested_in_if(x)
    if x > 10
      unless x > 20
        x * 2
      end
    end
  end
end
