# frozen_string_literal: true

require_relative "enum_macro"

class BreakdownMove
  extend EnumMacro

  STATUSES = {
    "pending" => "pending",
    "done" => "done"
  }.freeze

  enum :status, STATUSES

  attr_accessor :status

  def initialize(status)
    @status = status
  end
end
