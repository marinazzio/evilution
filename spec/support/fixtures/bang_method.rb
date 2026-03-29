class BangMethodExample
  def sort_bang(items)
    items.sort!
  end

  def sort_no_bang(items)
    items.sort
  end

  def map_bang(items)
    items.map! { |i| i * 2 }
  end

  def uniq_bang(items)
    items.uniq!
  end

  def save_bang(record)
    record.save!
  end

  def no_bang_method(items)
    items.length
  end

  def multiple_bangs(items)
    items.sort!
    items.uniq!
  end

  def strip_bang(str)
    str.strip!
  end
end
