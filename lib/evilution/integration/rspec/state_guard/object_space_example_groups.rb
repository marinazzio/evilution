# frozen_string_literal: true

require_relative "../../rspec"

class Evilution::Integration::RSpec::StateGuard; end unless defined?(Evilution::Integration::RSpec::StateGuard) # rubocop:disable Lint/EmptyClass

class Evilution::Integration::RSpec::StateGuard::ObjectSpaceExampleGroups
  def snapshot
    groups = Set.new
    ObjectSpace.each_object(Class) do |klass|
      groups << klass.object_id if klass < ::RSpec::Core::ExampleGroup
    rescue TypeError
      # ObjectSpace iteration may surface partially-initialized or anonymous
      # classes whose `<` comparison raises. Skipping them is safe — they
      # cannot be ExampleGroup descendants we need to track.
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
      rescue NameError
        # Constant may have been removed concurrently (e.g. via autoload
        # reload) between #constants(false) and #remove_const. Best-effort
        # cleanup — nothing to do if it's already gone.
      end

      klass.instance_variables.each do |ivar|
        klass.remove_instance_variable(ivar)
      end
    rescue TypeError
      # Same defensive case as #snapshot: skip classes whose `<` raises
      # mid-iteration.
    end
  end
end
