# frozen_string_literal: true

class CovFixtureLedger
  LIMIT = 100

  attr_reader :total

  def initialize
    @total = 0
  end

  def add(amount)
    @total += amount
  end

  def refund(amount)
    @total -= amount
  end
end
