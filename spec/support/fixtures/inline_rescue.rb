class InlineRescueExample
  def simple_inline_rescue
    dangerous_call rescue fallback_value
  end

  def inline_rescue_with_nil_fallback
    dangerous_call rescue nil
  end

  def inline_rescue_in_assignment
    result = dangerous_call rescue default_value
    result
  end

  def no_rescue
    safe_call
  end

  def multiple_inline_rescues
    a = first_call rescue default_a
    b = second_call rescue default_b
    [a, b]
  end
end
