# frozen_string_literal: true

require "active_support"
require "active_support/concern"

module Publishable
  extend ActiveSupport::Concern

  HIDDEN = [].freeze

  included do
    track :publishable
    scope :visible, lambda { |admin|
      if admin
        rows.reject { |row| HIDDEN.include?(row[:title]) }
      else
        rows.select { |row| row[:published] }
      end
    }
  end
end
