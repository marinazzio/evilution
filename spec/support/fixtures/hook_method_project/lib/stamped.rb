# frozen_string_literal: true

require "active_support"
require "active_support/concern"

module Stamped
  extend ActiveSupport::Concern

  prepended do
    track :stamped

    def self.stamp
      2
    end

    def self.unstamped
      4
    end
  end
end
