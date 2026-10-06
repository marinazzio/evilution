# frozen_string_literal: true

require "active_support"
require "active_support/concern"
require "aasm"

module Shippable
  extend ActiveSupport::Concern

  included do
    include AASM

    attr_accessor :address, :express, :courier

    aasm do
      after_all_transitions -> { self.transitions_seen = transitions_seen.to_i + 1 }
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
      event :refund do
        transitions from: :paid, to: :paid
      end
    end
  end
end
