class CollectionProcessor
  def transform(items)
    items.map { |i| i * 2 }
  end

  def iterate(items)
    items.each { |i| puts i }
  end

  def filter_in(items)
    items.select { |i| i > 0 }
  end

  def filter_out(items)
    items.reject { |i| i < 0 }
  end

  def flatten_transform(items)
    items.flat_map { |i| [i, i * 2] }
  end

  def collect_items(items)
    items.collect { |i| i.to_s }
  end
end
