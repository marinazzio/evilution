# frozen_string_literal: true

require_relative "../validators"

class Evilution::Parallel::WorkQueue::Validators::PositiveInt
  def self.call!(name, value)
    return if value.is_a?(Integer) && value >= 1

    raise ArgumentError, "#{name} must be a positive integer, got #{value.inspect}"
  end
end
