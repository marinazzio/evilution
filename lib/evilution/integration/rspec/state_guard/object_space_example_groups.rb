# frozen_string_literal: true

require_relative "../../rspec"

class Evilution::Integration::RSpec::StateGuard; end unless defined?(Evilution::Integration::RSpec::StateGuard) # rubocop:disable Lint/EmptyClass

class Evilution::Integration::RSpec::StateGuard::ObjectSpaceExampleGroups
  def snapshot
    groups = Set.new
    ObjectSpace.each_object(Class) do |klass|
      groups << klass.object_id if klass < ::RSpec::Core::ExampleGroup
    rescue TypeError # rubocop:disable Lint/SuppressedException
    end
    groups
  end

  def release(eg_before)
    return unless eg_before

    ObjectSpace.each_object(Class) do |klass|
      next unless klass < ::RSpec::Core::ExampleGroup
      next if eg_before.include?(klass.object_id)

      klass.constants(false).each do |const|
        klass.send(:remove_const, const)
      rescue NameError # rubocop:disable Lint/SuppressedException
      end

      klass.instance_variables.each do |ivar|
        klass.remove_instance_variable(ivar)
      end
    rescue TypeError # rubocop:disable Lint/SuppressedException
    end
  end
end
