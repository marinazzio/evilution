class BlockPassRemovalExample
  def with_symbol_block_pass(items)
    items.map(&:to_s)
  end

  def with_predicate_block_pass(items)
    items.select(&:valid?)
  end

  def no_block_pass(items)
    items.sort
  end

  def with_regular_block(items)
    items.map { |x| x * 2 }
  end

  def with_method_object_block_pass(items)
    items.map(&method(:process))
  end

  def chained_with_block_pass(items)
    items.select(&:present?).map(&:to_s)
  end

  def block_pass_no_args
    each(&:freeze)
  end

  def with_args_and_block_pass(items)
    items.inject(0, &:+)
  end

  private

  def process(item)
    item.to_s
  end
end
