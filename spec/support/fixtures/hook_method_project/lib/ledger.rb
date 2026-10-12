# frozen_string_literal: true

require "record"
require "tracked"
require "stamped"

class Ledger < Record
  include Tracked
  prepend Stamped

  def kind
    "ledger"
  end
end
