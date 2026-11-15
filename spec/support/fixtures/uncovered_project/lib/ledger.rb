# frozen_string_literal: true

class Ledger
  LIMIT = 100

  attr_reader :total

  def initialize
    @total = 0
  end

  def add(amount)
    @total += amount
  end

  def refund(amount)
    @total -= amount * 2
  end
end
