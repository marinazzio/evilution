# frozen_string_literal: true

require "record"
require "publishable"

class Post < Record
  include Publishable
end
