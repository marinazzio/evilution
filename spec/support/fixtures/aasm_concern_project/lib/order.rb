# frozen_string_literal: true

require "shippable"

class Order
  attr_accessor :transitions_seen

  include Shippable
end
