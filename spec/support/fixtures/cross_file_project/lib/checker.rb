# frozen_string_literal: true

require "limits"

module Checker
  def self.within?(value)
    value + Limits.step <= Limits::MAX + 1
  end

  def self.unused
    1
  end
end
