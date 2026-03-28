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
end
