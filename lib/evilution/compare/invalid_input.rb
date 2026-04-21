# frozen_string_literal: true

require_relative "../compare"

class Evilution::Compare::InvalidInput < StandardError
  attr_reader :index

  def initialize(message, index: nil)
    super(message)
    @index = index
  end
end
