class MethodBodyExample
  def with_body
    42
  end

  def with_complex_body
    x = 1
    y = 2
    x + y
  end

  def empty_method
  end

  def with_super_in_body
    super
    42
  end

  def with_forwarding_super(...)
    super(...)
  end
end
