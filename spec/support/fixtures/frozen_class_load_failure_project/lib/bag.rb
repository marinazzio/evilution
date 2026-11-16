# frozen_string_literal: true

# Its empty instance is built while the class body is evaluated, and more of
# the body follows it: a mutant that freezes the class there makes the rest of
# the body raise.
class Bag
  def initialize(items)
    @items = items
  end

  EMPTY = Bag.new([].freeze).freeze

  def size
    @items.size
  end

  def empty?
    size.zero?
  end
end
