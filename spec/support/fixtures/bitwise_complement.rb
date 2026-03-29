# frozen_string_literal: true

class BitwiseComplement
  def complement(a)
    ~a
  end

  def complement_expression(a, b)
    ~(a + b)
  end
end
