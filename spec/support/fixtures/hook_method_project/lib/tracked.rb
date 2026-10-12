# frozen_string_literal: true

require "active_support"
require "active_support/concern"

module Tracked
  extend ActiveSupport::Concern

  included do
    track :tracked

    def self.level
      1
    end

    def label
      "tracked"
    end

    def kind
      "tracked"
    end

    def self.unused
      3
    end
  end
end
