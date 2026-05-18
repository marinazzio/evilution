class IvarExample
  def with_ivars
    @name = "hello"
    @count = 0
    @name
  end

  def single_ivar
    @result = compute
    @result
  end

  def no_ivars
    42
  end

  def nested_ivar
    @a = (@b = 1)
  end
end
