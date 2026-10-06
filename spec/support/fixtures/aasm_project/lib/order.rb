# frozen_string_literal: true

require "aasm"

class Order
  include AASM

  attr_accessor :address, :express, :courier

  aasm do
    after_all_transitions -> { $transitions = $transitions.to_i + 1 }
    state :paid, initial: true
    state :shipped
    event :ship, guard: lambda {
      if express
        courier == :fast
      else
        !address.nil?
      end
    } do
      transitions from: :paid, to: :shipped
    end
  end
end
