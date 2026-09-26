class BinaryOperandPromotionTarget
  def add(a, b)
    a + b
  end

  def bitwise(flags, mask)
    flags & mask
  end

  def shift(value, bits)
    value << bits
  end

  def call_operands(order)
    order.subtotal * order.tax_rate
  end

  def plus_zero(a)
    a + 0
  end

  def zero_plus(b)
    0 + b
  end

  def times_one(a)
    a * 1
  end

  def plus_float_zero(a)
    a + 0.0
  end

  def void_append(result, item)
    result << item
    result
  end

  def comparison(a, b)
    a == b
  end
end
