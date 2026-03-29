# frozen_string_literal: true

class IndexAccess
  def hash_access(h)
    h[:key]
  end

  def array_access(a)
    a[0]
  end

  def string_key_access(h)
    h["name"]
  end

  def variable_key_access(h, k)
    h[k]
  end

  def multi_arg_access(a)
    a[1, 3]
  end

  def no_index_access
    "plain"
  end
end
