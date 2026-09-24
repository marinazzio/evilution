class CallToNilTarget
  def bare_call
    compute
  end

  def with_receiver(user)
    user.name
  end

  def with_arguments(list)
    format_all(list, ", ")
  end

  def chained(user)
    user.profile.name
  end

  def binary(a, b)
    a + b
  end

  def assigned(user)
    name = user.name
    name
  end

  def void_statement(logger, value)
    logger.info(value)
    value
  end

  def attribute_write(user, value)
    user.name = value
  end

  def index_write(hash, value)
    hash[:key] = value
  end

  def with_block(items)
    items.map { |item| [item] }
  end

  def predicate(user)
    user.admin?
  end

  def nested_argument(user)
    render(user.name)
  end
end
