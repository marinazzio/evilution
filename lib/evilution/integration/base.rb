# frozen_string_literal: true

class Evilution::Integration::Base
  def call(mutation)
    raise NotImplementedError, "#{self.class}#call must be implemented"
  end
end
