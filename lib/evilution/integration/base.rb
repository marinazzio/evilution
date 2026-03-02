# frozen_string_literal: true

module Evilution
  module Integration
    class Base
      def call(mutation)
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end
    end
  end
end
