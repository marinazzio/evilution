class HashChecker
  def returns_populated_hash
    { a: 1, b: 2 }
  end

  def returns_empty_hash
    {}
  end

  def returns_nested_hash
    { a: { b: 1 } }
  end
end
