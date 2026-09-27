class BlockBodyToRaiseTarget
  def brace_block(items)
    items.map { |item| item * 2 }
  end

  def do_block(items)
    items.each do |item|
      log(item)
      store(item)
    end
  end

  def with_rescue(items)
    items.each do |item|
      store(item)
    rescue StandardError
      skip(item)
    end
  end

  def with_ensure(items)
    items.each do |item|
      store(item)
    ensure
      flush
    end
  end

  def empty_block(items)
    items.each {}
  end

  def already_raises(items)
    items.each { raise }
  end

  def kernel_loop(queue)
    loop do
      item = queue.pop
      break if item.nil?
    end
  end

  def block_pass(items, fn)
    items.map(&fn)
  end
end
