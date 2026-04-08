# frozen_string_literal: true

class MultibyteExample
  WORDS = %w[привет мир].freeze

  def greeting
    WORDS.join(" ")
  end

  def length
    WORDS.sum(&:length)
  end
end
