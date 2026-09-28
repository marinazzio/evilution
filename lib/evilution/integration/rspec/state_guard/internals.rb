# frozen_string_literal: true

require_relative "../state_guard"
require_relative "../../rspec"

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
