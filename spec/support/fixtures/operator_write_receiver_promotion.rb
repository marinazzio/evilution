class OperatorWriteReceiverPromotionTarget
  def add_assign(amount)
    @account.balance += amount
  end

  def subtract_assign
    @stock.count -= 1
    @stock
  end

  def shift_assign(item)
    @queue.items <<= item
  end

  def safe_navigation(amount)
    @account&.balance += amount
  end

  def expression_value(first, second)
    @totals.sum += first * second
  end

  def in_block(amounts)
    amounts.each { |amount| @account.balance += amount }
  end

  def nested_write
    @account.balance += (@stock.count -= 1)
  end

  def local_receiver(account, amount)
    account.balance += amount
  end

  def self_receiver(amount)
    self.balance += amount
  end

  def chained_receiver(amount)
    @user.account.balance += amount
  end

  def class_variable_receiver(amount)
    @@registry.size += amount
  end

  def logical_write(value)
    @account.owner ||= value
  end

  def index_write(key)
    @counts[key] += 1
  end

  def plain_write(amount)
    @account.balance = amount
  end

  def variable_write(amount)
    @balance += amount
  end
end
