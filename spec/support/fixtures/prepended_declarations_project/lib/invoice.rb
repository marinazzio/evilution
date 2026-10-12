# frozen_string_literal: true

require "record"
require "audited"

class Invoice < Record
  prepend Audited
end
