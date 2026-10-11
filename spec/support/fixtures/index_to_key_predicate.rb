class IndexToKeyPredicateTarget
  def symbol_key(config)
    config[:size]
  end

  def variable_key(hash, key)
    hash[key]
  end

  def string_key(headers)
    headers["Accept"]
  end

  def chained_receiver(request, key)
    request.params[key]
  end

  def in_condition(config)
    config[:verbose] ? 1 : 2
  end

  def compared(config, expected)
    config[:mode] == expected
  end

  def assigned(hash, key)
    value = hash[key]
    value
  end

  def nested_lookup(table, row, column)
    table[row][column]
  end

  def safe_navigation(hash, key)
    hash&.[](key)
  end

  def void_statement(hash, key)
    hash[key]
    true
  end

  def integer_index(list)
    list[0]
  end

  def negative_index(list)
    list[-1]
  end

  def range_index(list)
    list[1..]
  end

  def multiple_arguments(matrix, row, column)
    matrix[row, column]
  end

  def splat_argument(hash, keys)
    hash[*keys]
  end

  def no_arguments(factory)
    factory[]
  end

  def index_write(hash, key, value)
    hash[key] = value
  end

  def index_or_write(hash, key)
    hash[key] ||= 1
  end

  def named_call(hash, key)
    hash.fetch(key)
  end
end
