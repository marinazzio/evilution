# frozen_string_literal: true

class LoopFlipExample
  def simple_while(x)
    while x > 0 # rubocop:disable Style/WhileUntilModifier
      x -= 1
    end
  end

  def simple_until(x)
    until x > 0 # rubocop:disable Style/WhileUntilModifier
      x += 1
    end
  end

  def modifier_while(x)
    x -= 1 while x > 0
  end

  def modifier_until(x)
    x += 1 until x > 0
  end

  def while_with_break(items)
    i = 0
    while i < items.length
      break if items[i].nil?

      i += 1
    end
    i
  end
end
