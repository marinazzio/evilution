# frozen_string_literal: true

require "order"

class PriorityOrder < Order
  before_validation :own_step

  def own_step = steps << :own
end
