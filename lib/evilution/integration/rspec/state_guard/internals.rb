# frozen_string_literal: true

require_relative "../../rspec"

class Evilution::Integration::RSpec::StateGuard; end unless defined?(Evilution::Integration::RSpec::StateGuard) # rubocop:disable Lint/EmptyClass

module Evilution::Integration::RSpec::StateGuard::Internals
  module_function

  def world_ivar(name)
    world = ::RSpec.world
    world.instance_variable_defined?(name) ? world.instance_variable_get(name) : nil
  end

  def config_ivar(name)
    config = ::RSpec.configuration
    config.instance_variable_defined?(name) ? config.instance_variable_get(name) : nil
  end
end
