class ToIToIntegerTarget
  def plain(value)
    value.to_i
  end

  def with_base(value)
    value.to_i(16)
  end

  def compound_receiver(params)
    params[:page].to_i
  end

  def safe_navigation(value)
    value&.to_i
  end

  def integer_literal
    42.to_i
  end

  def float_literal
    3.7.to_i
  end

  def receiverless
    to_i
  end

  def other_method(value)
    value.to_f
  end
end
