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

  def iterate_keys(hash)
    hash.each_key { |k| puts k }
  end

  def iterate_values(hash)
    hash.each_value { |v| puts v }
  end

  def assoc_lookup(hash, key)
    hash.assoc(key)
  end

  def rassoc_lookup(hash, val)
    hash.rassoc(val)
  end

  def grep_items(items)
    items.grep(Integer)
  end

  def grep_v_items(items)
    items.grep_v(Integer)
  end

  def take_items(items)
    items.take(3)
  end

  def drop_items(items)
    items.drop(3)
  end

  def min_item(items)
    items.min
  end

  def max_item(items)
    items.max
  end

  def min_by_item(items)
    items.min_by { |i| i.length }
  end

  def max_by_item(items)
    items.max_by { |i| i.length }
  end

  def compact_items(items)
    items.compact
  end

  def flatten_items(items)
    items.flatten
  end

  def zip_items(a, b)
    a.zip(b)
  end

  def product_items(a, b)
    a.product(b)
  end
end
