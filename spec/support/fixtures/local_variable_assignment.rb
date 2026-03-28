class LocalVarExample
  def with_assignments
    x = 42
    y = compute(x)
    x + y
  end

  def single_assignment
    result = expensive_call
    result
  end

  def no_assignments
    42
  end
end
