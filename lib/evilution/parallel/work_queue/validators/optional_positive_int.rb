# frozen_string_literal: true

require_relative "../validators"

class Evilution::Parallel::WorkQueue::Validators::OptionalPositiveInt
  def self.call!(name, value)
    return if value.nil? || (value.is_a?(Integer) && value.positive?)

    raise ArgumentError, "#{name} must be nil or a positive integer, got #{value.inspect}"
  end
end
