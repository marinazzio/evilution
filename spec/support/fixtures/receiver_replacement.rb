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

  def self_class_bare
    self.class
  end

  def self_class_chained
    self.class.new
  end

  def self_class_const_path
    self.class::Handler
  end

  def self_then_chained
    self.then { |x| x }
  end

  def is_a_self_class(other)
    other.is_a?(self.class)
  end

  class Handler
  end
end
