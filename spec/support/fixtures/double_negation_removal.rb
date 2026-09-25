class DoubleNegationTarget
  def coerce(value)
    !!value
  end

  def coerce_call(user)
    !!user.admin
  end

  def coerce_group(a, b)
    !!(a && b)
  end

  def keyword_form(value)
    not not value
  end

  def single_negation(value)
    !value
  end

  def in_condition(value)
    return 1 if !!value

    0
  end
end
