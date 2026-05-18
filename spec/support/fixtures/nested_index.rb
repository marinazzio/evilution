# frozen_string_literal: true

class NestedIndex
  def two_level(h)
    h[:a][:b]
  end

  def three_level(h)
    h[:a][:b][:c]
  end

  def mixed_keys(h)
    h["users"][0][:name]
  end

  def single_level(h)
    h[:key]
  end

  def no_index
    "plain"
  end

  def nested_in_argument(x, y)
    x[y[:a][:b]]
  end

  def index_then_call(h)
    h[:a].bar
  end

  def self_index
    self[:a][:b]
  end

  def method_chain(a)
    a.foo(1).bar(2)
  end

  def empty_index_chain(h)
    h[][:b]
  end

  def two_arg_index(h)
    h[:a, :b][:c]
  end
end
