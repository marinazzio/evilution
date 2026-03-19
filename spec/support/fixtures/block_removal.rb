class BlockRemovalExample
  def with_block(items)
    items.map { |x| x * 2 }
  end

  def with_do_block(items)
    items.each do |x|
      puts x
    end
  end

  def no_block(items)
    items.sort
  end

  def with_self_block
    self.tap { |x| x.freeze }
  end

  def chained_blocks(items)
    items.select { |x| x > 0 }.map { |x| x.to_s }
  end

  def block_no_receiver
    loop { break }
  end
end
