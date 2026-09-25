class ArgumentListRemovalTarget
  def several(a, b)
    combine(a, b)
  end

  def single(value)
    normalize(value)
  end

  def with_receiver(formatter, value)
    formatter.format(value, 2)
  end

  def without_parens(value)
    puts value
  end

  def keywords
    build(name: "x", size: 2)
  end

  def splat(values)
    combine(*values)
  end

  def block_pass(items, block)
    items.each_slice(2, &block)
  end

  def block_pass_without_parens(items, block)
    items.each_slice 2, &block
  end

  def literal_block(items)
    items.each_slice(2) { |pair| pair }
  end

  def only_block_pass(items, block)
    items.each(&block)
  end

  def no_arguments
    compute
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

  def call_shorthand(callable, value)
    callable.(value)
  end

  def void_statement(logger, value)
    logger.info(value)
    value
  end
end
