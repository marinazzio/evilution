class MixinExample
  include Comparable
  extend ClassMethods
  prepend Logging

  def first_method
    42
  end

  def second_method
    "hello"
  end
end

class NoMixinExample
  def plain_method
    true
  end
end

class MultipleMixinExample
  include Enumerable
  include Comparable

  def with_multiple
    :ok
  end
end
