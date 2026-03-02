class BooleanChecker
  def always_true
    true
  end

  def always_false
    false
  end

  def mixed_booleans(flag)
    return true if flag
    false
  end
end
