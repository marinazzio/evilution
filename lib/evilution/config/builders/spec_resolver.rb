# frozen_string_literal: true

require_relative "../builders"
require_relative "../../spec_resolver"

class Evilution::Config::Builders::SpecResolver
  def self.call(integration:)
    case integration
    when :minitest
      Evilution::SpecResolver.new(test_dir: "test", test_suffix: "_test.rb", request_dir: "integration")
    else
      Evilution::SpecResolver.new
    end
  end
end
