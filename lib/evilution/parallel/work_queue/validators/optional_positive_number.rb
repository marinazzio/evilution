# frozen_string_literal: true

require_relative "../validators"

class Evilution::Parallel::WorkQueue::Validators::OptionalPositiveNumber
  def self.call!(name, value)
    return if value.nil? || (value.is_a?(Numeric) && value.positive?)

    raise ArgumentError, "#{name} must be nil or a positive number, got #{value.inspect}"
  end
end
