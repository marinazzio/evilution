# frozen_string_literal: true

module Operators
  NAMES = %w[add sub].map(&:to_sym).freeze

  def self.known?(name)
    NAMES.include?(name)
  end
end
