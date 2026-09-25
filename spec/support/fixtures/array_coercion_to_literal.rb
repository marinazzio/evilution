class ArrayCoercionTarget
  def implicit(value)
    Array(value)
  end

  def kernel_dot(value)
    Kernel.Array(value)
  end

  def kernel_colons(value)
    Kernel::Array(value)
  end

  def without_parens(value)
    Array value
  end

  def compound_argument(options)
    Array(options[:ids])
  end

  def other_receiver(value)
    Converter.Array(value)
  end

  def splat(values)
    Array(*values)
  end

  def no_argument
    Array()
  end

  def other_method(value)
    Hash(value)
  end
end
