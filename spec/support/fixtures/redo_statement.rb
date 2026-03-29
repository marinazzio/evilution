class RedoStatementExample
  def simple_redo
    items.each do |item|
      redo if item.retry?
      process(item)
    end
  end

  def redo_in_loop
    loop do
      result = fetch_next
      redo unless result.valid?
      handle(result)
    end
  end

  def no_redo
    items.each do |item|
      process(item)
    end
  end

  def multiple_redos
    items.each do |item|
      redo if item.stale?
      redo if item.retry?
      process(item)
    end
  end
end
