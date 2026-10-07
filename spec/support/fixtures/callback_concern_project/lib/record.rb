# frozen_string_literal: true

require "active_model"

class Record
  include ActiveModel::Model
  include ActiveModel::Validations::Callbacks

  attr_accessor :title, :total, :paid, :rush, :steps

  def initialize(attributes = {})
    super
    @steps = []
  end
end
