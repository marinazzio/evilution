class BlockBodyPromotionTarget
  def single_statement(account)
    Base.transaction { account.save! }
  end

  def multi_statement(record)
    Base.transaction do
      record.lock!
      record.update!(state: :done)
      record
    end
  end

  def value_position(record)
    result = record.with_lock do
      record.touch
      record.reload
    end
    result
  end

  def with_parameters(items)
    items.each { |item| process(item) }
  end

  def numbered_parameter(items)
    items.each { process(_1) }
  end

  def with_break(queue)
    loop do
      break if queue.empty?
    end
  end

  def with_rescue
    Base.transaction do
      charge
    rescue StandardError
      refund
    end
  end

  def empty_block
    Base.transaction {}
  end

  def block_pass(items, fn)
    items.each(&fn)
  end
end
