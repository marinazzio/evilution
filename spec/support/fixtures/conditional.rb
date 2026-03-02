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
end
