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
end
