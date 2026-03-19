class ReceiverReplacementExample
  def with_self
    self.name
  end

  def self_with_args(x)
    self.compute(x)
  end

  def self_with_block
    self.tap { |x| x }
  end

  def no_self(obj)
    obj.name
  end

  def implicit_self
    name
  end

  def self_setter(val)
    self.name = val
  end
end
