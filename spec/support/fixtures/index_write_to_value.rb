class IndexWriteToValueTarget
  def sole_statement(cache, key, value)
    cache[key] = value
  end

  def last_statement(cache, key, value)
    prepare
    cache[key] = value
  end

  def expression_value(counts, key, step)
    counts[key] = step + 1
  end

  def call_value(cache, key)
    cache[key] = compute(key)
  end

  def multiple_indexes(matrix, row, column, value)
    matrix[row, column] = value
  end

  def chained_receiver(session, key, value)
    session.data[key] = value
  end

  def guarded(cache, key, value)
    cache[key] = value if value
  end

  def in_block(cache, keys)
    keys.each { |key| cache[key] = 1 }
  end

  def in_value_position(cache, key, value)
    stored = (cache[key] = value)
    stored
  end

  def explicit_call(cache, key, value)
    cache.[]=(key, value)
  end

  def safe_navigation(cache, key, value)
    cache&.[]=(key, value)
  end

  def void_statement(cache, key, value)
    cache[key] = value
    cache
  end

  def list_value(cache, key, first, second)
    cache[key] = first, second
  end

  def operator_write(cache, key)
    cache[key] ||= 1
  end

  def compound_write(counts, key)
    counts[key] += 1
  end

  def multiple_assignment(cache, key, pair)
    cache[key], other = pair
    other
  end

  def attribute_write(user, value)
    user.name = value
  end

  def index_read(cache, key)
    cache[key]
  end
end
