class MethodCallExample
  def with_receiver(items)
    items.map { |x| x * 2 }
  end

  def chained(items)
    items.select(&:valid?).first
  end

  def without_receiver(x)
    puts(x)
  end

  def with_self
    self.name
  end

  def with_args(obj, a, b)
    obj.compute(a, b)
  end

  def no_args(obj)
    obj.save
  end

  def conversion(value)
    value.to_s
  end
end
