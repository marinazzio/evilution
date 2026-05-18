# frozen_string_literal: true

class IndexAssignment
  def hash_assign(h)
    h[:key] = "value"
    h
  end

  def array_assign(a)
    a[0] = 42
    a
  end

  def nested_assign(h)
    h[:a] = 1
    h[:b] = 2
    h
  end

  def no_assignment
    "plain"
  end

  def index_in_index_value(h, g)
    h[g[1] = 2] = 3
  end

  def regular_method_call(obj)
    obj.compute(1)
  end
end
