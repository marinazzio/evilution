# frozen_string_literal: true

require_relative "../state_guard"
require_relative "../../rspec"
require_relative "../../../class_tree"

# Empties the example groups a run defined of their constants and instance
# variables, so that what they hold does not outlive the run in a process
# that runs more than one.
#
# The groups are found below ExampleGroup in the class tree rather than among
# every class on the heap: a heap walk, twice a run, touched every object the
# process holds.
class Evilution::Integration::RSpec::StateGuard::ExampleGroupDescendants
  def snapshot
    Set.new(descendants.map(&:object_id))
  end

  def release(eg_before)
    return unless eg_before

    descendants.each do |klass|
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
    end
  end

  private

  def descendants
    Evilution::ClassTree.descendants(::RSpec::Core::ExampleGroup)
  end
end
