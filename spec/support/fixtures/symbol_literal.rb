class SymbolChecker
  def returns_foo
    :foo
  end

  def uses_hash_rocket
    { :foo => 1 }
  end

  def uses_kwarg_label
    { foo: 1 }
  end

  def calls_with_kwarg
    some_method(bar: 2)
  end

  def mixes_symbol_and_label
    some_method(:literal, key: 3)
  end

  def rounds_half_even(amount)
    amount.round(2, half: :even)
  end

  def rounds_and_names(amount)
    [amount.round(2, half: :even), :even]
  end

  def rounds_unknown_mode(amount)
    amount.round(2, half: :banker)
  end

  def half_keyword_elsewhere
    configure(half: :even)
  end
end
