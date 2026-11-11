# frozen_string_literal: true

class Pricing
  TAX_RATE = 0.2
  BULK_THRESHOLD = 10

  def initialize(unit_price)
    @unit_price = unit_price
  end

  def subtotal(quantity)
    return 0 if quantity <= 0

    total = @unit_price * quantity
    quantity >= BULK_THRESHOLD ? total * 0.9 : total
  end

  def with_tax(quantity)
    (subtotal(quantity) * (1 + TAX_RATE)).round(2)
  end

  def discount_label(quantity)
    if quantity >= BULK_THRESHOLD * 5
      "wholesale"
    elsif quantity >= BULK_THRESHOLD
      "bulk"
    else
      "retail"
    end
  end
end
