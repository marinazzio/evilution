class CollectionReturnExample
  def returns_array
    [1, 2, 3]
  end

  def returns_hash
    { a: 1, b: 2 }
  end

  def returns_empty_array
    []
  end

  def returns_empty_hash
    {}
  end

  def returns_string
    "hello"
  end

  def returns_nil
    nil
  end

  def returns_integer
    42
  end

  def multi_line_returns_array
    x = compute
    [x, x + 1]
  end

  def multi_line_returns_hash
    key = :name
    { key => "value" }
  end

  def empty_method
  end
end
