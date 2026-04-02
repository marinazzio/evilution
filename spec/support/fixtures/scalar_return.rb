class ScalarReturnExample
  def returns_string
    "hello"
  end

  def returns_integer
    42
  end

  def returns_float
    3.14
  end

  def returns_empty_string
    ""
  end

  def returns_zero
    0
  end

  def returns_zero_float
    0.0
  end

  def returns_array
    [1, 2]
  end

  def returns_nil
    nil
  end

  def multi_line_returns_string
    x = compute
    "done"
  end

  def multi_line_returns_integer
    x = compute
    42
  end

  def multi_line_returns_float
    x = compute
    3.14
  end

  def multi_line_returns_zero
    x = compute
    0
  end

  def multi_line_returns_empty_string
    x = compute
    ""
  end

  def multi_line_returns_zero_float
    x = compute
    0.0
  end

  def empty_method
  end
end
