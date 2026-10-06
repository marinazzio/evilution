# frozen_string_literal: true

require "active_model"

class Order
  include ActiveModel::Model
  include ActiveModel::Validations::Callbacks

  attr_accessor :title, :total, :paid, :rush, :steps

  before_validation :first_step
  before_validation do
    if rush
      steps << :rushed
    else
      steps << :queued
    end
  end
  before_validation :last_step

  validate :credit_limit, if: lambda {
    if rush
      total > 1000
    else
      paid == true
    end
  }
  validates :title, presence: true, unless: lambda {
    if rush
      total.zero?
    else
      paid == true
    end
  }

  def initialize(attributes = {})
    super
    @steps = []
  end

  def first_step = steps << :first

  def last_step = steps << :last

  def credit_limit
    errors.add(:total, "over the limit") if total > 100
  end
end
