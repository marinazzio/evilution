# frozen_string_literal: true

require "shippable"

class Parcel
  attr_accessor :transitions_seen

  include Shippable
end
