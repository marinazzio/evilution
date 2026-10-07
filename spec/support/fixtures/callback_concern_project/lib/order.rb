# frozen_string_literal: true

require "record"
require "reviewable"

class Order < Record
  include Reviewable
end

class PriorityOrder < Order
  before_validation :own_step

  def own_step = steps << :own
end
