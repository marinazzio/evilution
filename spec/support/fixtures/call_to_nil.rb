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

  def operator_write_receiver(user)
    user.account.total += bonus
  end

  def or_write_receiver(user)
    user.profile.name ||= default_name
  end

  def and_write_receiver(user)
    user.profile.name &&= default_name
  end

  def index_operator_write_receiver(key)
    counts[key] += step
  end

  def index_or_write_receiver(key)
    cache[key] ||= compute(key)
  end

  def index_and_write_receiver(key)
    cache[key] &&= compute(key)
  end

  def multiple_assignment_receivers(pair)
    account.owner, store[slot] = pair
    pair
  end

  def singleton_on_call
    def helper.extra = compute
    finish
  end

  def singleton_class_of_call
    class << registry
      attr_reader :entries
    end
    finish
  end
end
