class ArgumentPropagationTarget
  def bare(value)
    normalize(value)
  end

  def with_receiver(formatter, value)
    formatter.format(value)
  end

  def without_parens(value)
    Integer value
  end

  def two_arguments(a, b)
    combine(a, b)
  end

  def no_arguments
    compute
  end

  def keyword_only
    build(name: "x")
  end

  def splat(values)
    combine(*values)
  end

  def block_argument(block)
    run(&block)
  end

  def binary(a, b)
    a + b
  end

  def index_read(list, i)
    list[i]
  end

  def attribute_write(user, value)
    user.name = value
  end

  def void_statement(logger, value)
    logger.info(value)
    value
  end

  def with_block(items)
    wrap(items) { |item| item }
  end

  def nested(value)
    outer(inner(value))
  end
end
