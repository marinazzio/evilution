# frozen_string_literal: true

require_relative "../../rspec"

class Evilution::Integration::RSpec::StateGuard; end unless defined?(Evilution::Integration::RSpec::StateGuard) # rubocop:disable Lint/EmptyClass

class Evilution::Integration::RSpec::StateGuard::ExampleGroupsConstants
  def snapshot
    return nil unless defined?(::RSpec::ExampleGroups)

    Set.new(::RSpec::ExampleGroups.constants(false))
  end

  def release(before)
    return unless before
    return unless defined?(::RSpec::ExampleGroups)

    ::RSpec::ExampleGroups.constants(false).each do |c|
      next if before.include?(c)

      begin
        ::RSpec::ExampleGroups.send(:remove_const, c)
      rescue NameError
        next
      end
    end
  end
end
