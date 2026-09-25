class ReduceToSumTarget
  def reduce_symbol(values)
    values.reduce(:+)
  end

  def inject_symbol(values)
    values.inject(:+)
  end

  def with_initial(values)
    values.reduce(10, :+)
  end

  def block_pass(values)
    values.inject(&:+)
  end

  def block_pass_with_initial(values)
    values.reduce(0, &:+)
  end

  def without_parens(values)
    values.reduce :+
  end

  def safe_navigation(values)
    values&.reduce(:+)
  end

  def other_operator(values)
    values.reduce(:*)
  end

  def literal_block(values)
    values.reduce(0) { |sum, value| sum + value }
  end

  def other_method(values)
    values.each_slice(:+)
  end

  def no_arguments(values)
    values.reduce
  end

  def implicit_receiver
    reduce(:+)
  end
end
