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

  def nested_call(a, b, c)
    outer(inner(a, b), c)
  end

  def splat_among_positional(a, rest)
    bar(a, *rest)
  end

  def kwarg_among_positional(a, val)
    bar(a, key: val)
  end

  def index_assign(h, k, v)
    h[k] = v
  end

  def multi_index_assign(h, k, l, v)
    h[k, l] = v
  end

  def array_index_assign(arr, i, x)
    arr[i] = x
  end

  def heredoc_arg
    raise ArgumentError, <<~MSG.strip
      Could not find policy
    MSG
  end

  def two_heredocs
    Logger.info(<<~A, <<~B)
      first
    A
      second
    B
  end

  # Validates the heredoc-skip heuristic: a replacement that contains a
  # `<<` shift/append operator (NOT a heredoc anchor) must NOT trigger the
  # skip branch even when the byte range contains a real heredoc anchor.
  def shift_arg_with_heredoc(arr, x)
    raise ArgumentError, (arr << x), <<~MSG.strip
      could not append
    MSG
  end
end
