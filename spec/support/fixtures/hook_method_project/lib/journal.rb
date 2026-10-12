# frozen_string_literal: true

require "record"
require "tracked"
require "stamped"

class Journal < Record
  include Tracked
  prepend Stamped
end
