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

  def sort_items(items)
    items.sort { |a, b| a <=> b }
  end

  def sort_by_items(items)
    items.sort_by { |i| i.length }
  end

  def find_item(items)
    items.find { |i| i > 0 }
  end

  def detect_item(items)
    items.detect { |i| i > 0 }
  end

  def check_any(items)
    items.any? { |i| i > 0 }
  end

  def check_all(items)
    items.all? { |i| i > 0 }
  end

  def count_items(items)
    items.count
  end

  def length_items(items)
    items.length
  end

  def pop_item(items)
    items.pop
  end

  def shift_item(items)
    items.shift
  end

  def push_item(items, val)
    items.push(val)
  end

  def unshift_item(items, val)
    items.unshift(val)
  end
end
