class BreakStatementExample
  def break_without_value
    items.each do |item|
      break if item.nil?
      process(item)
    end
  end

  def break_with_value
    items.each do |item|
      break item.value if item.done?
      process(item)
    end
  end

  def simple_break
    loop do
      result = fetch_next
      break result if result
    end
  end

  def no_break
    items.each do |item|
      process(item)
    end
  end

  def multiple_breaks
    items.each do |item|
      break if item.nil?
      break :done if item.finished?
      process(item)
    end
  end
end
