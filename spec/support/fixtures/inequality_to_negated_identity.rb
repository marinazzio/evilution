class InequalityTarget
  def plain(a, b)
    a != b
  end

  def call_operands(user, other)
    user.id != other.id
  end

  def compound_left(a, b, c)
    a + b != c
  end

  def compound_right(a, b, c)
    a != b + c
  end

  def against_nil(value)
    value != nil
  end

  def nil_on_the_left(value)
    nil != value
  end

  def against_symbol(state)
    state != :done
  end

  def against_boolean(flag)
    flag != true
  end

  def equality(a, b)
    a == b
  end
end
