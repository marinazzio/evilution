class NextStatementExample
  def next_without_value
    items.each do |item|
      next if item.nil?
      process(item)
    end
  end

  def next_with_value
    items.map do |item|
      next item.default if item.skip?
      transform(item)
    end
  end

  def simple_next
    items.select do |item|
      next false unless item.valid?
      item.active?
    end
  end

  def no_next
    items.each do |item|
      process(item)
    end
  end

  def multiple_nexts
    items.map do |item|
      next if item.nil?
      next :default if item.empty?
      process(item)
    end
  end
end
