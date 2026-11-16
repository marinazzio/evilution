# frozen_string_literal: true

# Defines the class; crate_ext.rb reopens it.
class Crate
  def initialize(items)
    @items = items
  end

  def size
    @items.size
  end
end
