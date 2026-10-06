# frozen_string_literal: true

require "record"
require "publishable"

class Article < Record
  include Publishable
end
