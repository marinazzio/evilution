class ReturnValueExample
  def with_return_value(x)
    return x + 1
  end

  def bare_return(flag)
    return if flag
    42
  end
end
