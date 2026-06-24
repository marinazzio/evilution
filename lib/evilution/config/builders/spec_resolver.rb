# frozen_string_literal: true

require_relative "../builders"
require_relative "../../spec_resolver"

class Evilution::Config::Builders::SpecResolver
  def self.call(integration:)
    case integration
    when :minitest, :test_unit
      # test-unit gems mirror minitest's layout (test/ root, _test.rb suffix);
      # without this they default to spec/_spec.rb and resolve to nothing.
      Evilution::SpecResolver.new(test_dir: "test", test_suffix: "_test.rb", request_dir: "integration")
    else
      Evilution::SpecResolver.new
    end
  end
end
