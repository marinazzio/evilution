# frozen_string_literal: true

require "active_model"
require "active_support/concern"
require "aasm"

module Audited
  extend ActiveSupport::Concern

  prepended do
    include AASM

    track :audited

    scope :visible, lambda { |admin|
      if admin
        rows.reject { |row| row[:title].empty? }
      else
        rows.select { |row| row[:published] }
      end
    }

    before_validation do
      if rush
        steps << :rushed
      else
        steps << :queued
      end
    end

    validate :credit_limit, if: lambda {
      if rush
        total > 1000
      else
        paid == true
      end
    }

    aasm do
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

  def credit_limit
    errors.add(:total, "over the limit") if total > 100
  end
end
