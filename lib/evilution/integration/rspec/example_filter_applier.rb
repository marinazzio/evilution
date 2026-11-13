# frozen_string_literal: true

require_relative "../rspec"

module Evilution::Integration::RSpec::ExampleFilterApplier
  class Identity
    def call(_mutation, files)
      files
    end

    def warm(_mutation, _files); end
  end

  class Custom
    def initialize(filter)
      @filter = filter
    end

    def call(mutation, files)
      @filter.call(mutation, files)
    end

    # Only a filter that caches what it parses has anything to warm.
    def warm(mutation, files)
      @filter.warm(mutation, files) if @filter.respond_to?(:warm)
    end
  end
end
