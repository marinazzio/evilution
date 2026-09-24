class AttributeWriteTarget
  def only_write(user, value)
    user.name = value
  end

  def self_write(value)
    self.name = value
  end

  def safe_write(user, value)
    user&.name = value
  end

  def index_write(hash, value)
    hash[:key] = value
  end

  def guarded_write(user, value)
    user.name = value if value
  end

  def value_position(user, value)
    @last = (user.name = value)
  end

  def as_argument(user, value)
    log(user.name = value)
  end

  def in_multi_statement_body(user, value)
    user.name = value
    user.save
  end

  def plain_read(user)
    user.name
  end

  def comparison(a, b)
    a == b
  end
end
