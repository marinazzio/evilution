# frozen_string_literal: true

require "active_support"
require "active_support/concern"

module Auditable
  extend ActiveSupport::Concern

  prepended do
    audit :changes
  end

  def self.unused
    1
  end
end
