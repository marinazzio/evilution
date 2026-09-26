class CoercionEmptyingTarget
  def array(value)
    value.to_a
  end

  def implicit_array(value)
    value.to_ary
  end

  def hash(value)
    value.to_h
  end

  def implicit_hash(value)
    value.to_hash
  end

  def string(value)
    value.to_s
  end

  def implicit_string(value)
    value.to_str
  end

  def safe_navigation(value)
    value&.to_s
  end

  def bare_argument(value)
    render value.to_h
  end

  def parenthesized_argument(value)
    render(value.to_h)
  end

  def with_base(value)
    value.to_s(2)
  end

  def with_block(pairs)
    pairs.to_h { |pair| pair }
  end

  def nil_receiver
    nil.to_s
  end

  def receiverless
    to_s
  end
end
