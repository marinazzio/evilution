# frozen_string_literal: true

class BitwiseComplement
  def complement(a)
    ~a
  end

  def complement_expression(a, b)
    ~(a + b)
  end

  def nested_complement(a)
    ~(~a)
  end

  def predicate_call(a)
    a.zero?
  end
end
