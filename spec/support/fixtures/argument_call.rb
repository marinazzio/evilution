class ArgumentCallExample
  def two_args(obj, a, b)
    obj.compute(a, b)
  end

  def three_args(a, b, c)
    process(a, b, c)
  end

  def single_arg(x)
    transform(x)
  end

  def no_args
    reset()
  end

  def with_splat(*args)
    forward(*args)
  end

  def with_kwargs(a)
    configure(key: a)
  end

  def mixed_regular(a, b)
    send_data(a, b)
  end
end
