class SafeNavigationTarget
  def plain(user)
    user&.name
  end

  def with_arguments(user)
    user&.fetch(:name, "anon")
  end

  def chained(user)
    user&.profile&.name
  end

  def with_block(items)
    items&.map { |item| item }
  end

  def attribute_write(user, value)
    user&.name = value
  end

  def or_write(user)
    user&.name ||= "anon"
  end

  def and_write(user)
    user&.name &&= "anon"
  end

  def operator_write(counter)
    counter&.value += 1
  end

  def plain_call(user)
    user.name
  end

  def self_receiver
    self&.name
  end

  def literal_receivers
    ["a"&.upcase, [1]&.first, { a: 1 }&.keys, 1&.succ, :a&.to_s]
  end
end
