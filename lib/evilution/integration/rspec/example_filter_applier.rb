# frozen_string_literal: true

require_relative "../rspec"

module Evilution::Integration::RSpec::ExampleFilterApplier
  class Identity
    def call(_mutation, files)
      files
    end
  end

  class Custom
    def initialize(filter)
      @filter = filter
    end

    def call(mutation, files)
      @filter.call(mutation, files)
    end
  end
end
