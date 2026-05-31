# frozen_string_literal: true

require_relative "../test_unit"

# Loads the test-unit gem and disables its at_exit auto-run handler.
# Mirrors Evilution::Integration::RSpec::FrameworkLoader's role: framework
# setup is one responsibility separated from dispatch + result building so
# integrations can compose it independently in tests.
class Evilution::Integration::TestUnit::FrameworkLoader
  def loaded?
    @loaded == true
  end

  def call
    return if @loaded

    require "test-unit"
    self.class.stub_autorun!
    @loaded = true
  rescue LoadError => e
    raise Evilution::Error, "test-unit is required but not available: #{e.message}"
  end

  # User code that `require "test-unit"` installs an at_exit hook that calls
  # Test::Unit::AutoRunner.run when need_auto_run? is true. At evilution exit
  # ARGV still holds evilution flags and the runner prints a misleading banner.
  # Flipping need_auto_run = false prevents the handler from firing.
  def self.stub_autorun!
    return unless defined?(::Test::Unit::AutoRunner)

    ::Test::Unit::AutoRunner.need_auto_run = false
  end
end
