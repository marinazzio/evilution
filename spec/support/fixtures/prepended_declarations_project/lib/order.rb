# frozen_string_literal: true

require "record"
require "audited"

class Order < Record
  prepend Audited
end
