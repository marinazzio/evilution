class ConditionalExample
  def check_positive(x)
    if x > 0
      "positive"
    else
      "non-positive"
    end
  end

  def check_negative(x)
    unless x > 0
      "non-positive"
    else
      "positive"
    end
  end

  def nested_if(x, y)
    if x > 0
      if y > 0
        "both"
      end
    end
  end

  def nested_unless(x, y)
    unless x > 0
      unless y > 0
        "neither"
      end
    end
  end
end
