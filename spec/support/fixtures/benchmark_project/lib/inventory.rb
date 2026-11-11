# frozen_string_literal: true

class Inventory
  def initialize
    @items = {}
  end

  def add(name, count = 1)
    raise ArgumentError, "count must be positive" unless count.positive?

    @items[name] = @items.fetch(name, 0) + count
  end

  def remove(name, count = 1)
    current = @items.fetch(name, 0)
    return false if count > current

    remaining = current - count
    remaining.zero? ? @items.delete(name) : @items[name] = remaining
    true
  end

  def count(name)
    @items.fetch(name, 0)
  end

  def total
    @items.values.sum
  end

  def low_stock(threshold = 2)
    @items.select { |_, count| count <= threshold }.keys.sort
  end

  def names
    @items.keys.sort
  end
end
