# frozen_string_literal: true

# rubocop:disable Style/OneClassPerFile
module Evilution::Compare
end

class Evilution::Compare::InvalidInput < StandardError
  attr_reader :index

  def initialize(message, index: nil)
    super(message)
    @index = index
  end
end
# rubocop:enable Style/OneClassPerFile
