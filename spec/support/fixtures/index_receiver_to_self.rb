class IndexReceiverToSelfTarget
  def local_receiver(hash, key)
    hash[key]
  end

  def call_receiver(key)
    settings[key]
  end

  def chained_receiver(config, key)
    config.options[key]
  end

  def instance_variable_receiver(key)
    @store[key]
  end

  def multiple_arguments(list)
    list[1, 2]
  end

  def nested_index(table, row, column)
    table[row][column]
  end

  def assigned(hash, key)
    value = hash[key]
    value
  end

  def safe_navigation(hash, key)
    hash&.[](key)
  end

  def already_self(key)
    self[key]
  end

  def index_write(hash, key, value)
    hash[key] = value
  end

  def index_or_write(hash, key)
    hash[key] ||= 1
  end

  def array_literal(a, b)
    [a, b]
  end

  def named_call(hash, key)
    hash.fetch(key)
  end
end
