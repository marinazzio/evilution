# frozen_string_literal: true

require_relative "../integration"

class Evilution::Integration::Base
  def initialize(hooks: nil)
    @hooks = hooks
  end

  def call(mutation)
    raise NotImplementedError, "#{self.class}#call must be implemented"
  end
end
