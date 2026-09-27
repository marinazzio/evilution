class BlockBodyToNilTarget
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

  def empty_block(items)
    items.each {}
  end

  def nil_block(items)
    items.each { nil }
  end

  def kernel_loop(queue)
    loop do
      item = queue.pop
      break if item.nil?
    end
  end

  def endless_cycle(items)
    items.cycle { |item| process(item) }
  end

  def bounded_cycle(items)
    items.cycle(2) { |item| process(item) }
  end

  def lambda_block
    lambda { |x| x + 1 }
  end

  def block_pass(items, fn)
    items.map(&fn)
  end
end
