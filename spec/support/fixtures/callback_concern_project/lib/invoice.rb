# frozen_string_literal: true

require "record"
require "reviewable"

class Invoice < Record
  include Reviewable
end
