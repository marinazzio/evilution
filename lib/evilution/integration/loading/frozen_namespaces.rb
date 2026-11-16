# frozen_string_literal: true

require_relative "../loading"

# The classes and modules a file declares, as they stood before a mutant of the
# file was applied, and a way past a mutant that froze one of them.
#
# A mutant can freeze a class its own file declares: `List.freeze` in place of
# `List.new([].freeze).freeze`. The rest of the class body then raises
# FrozenError, and so does the original evaluated after it to tell whether the
# mutant broke the load, since it reopens the class the mutant froze. Ruby
# cannot thaw an object, so the frozen class is set aside instead: its
# constant is removed and the original defines it afresh, as
# RedefinitionRecovery does for a class body that rejects being declared
# twice. Whatever still holds the old class keeps holding it.
#
# Only a class or module the file declares is set aside, and only one that was
# not frozen before the mutant was applied: a file that freezes its own class
# as it loads cannot be evaluated again, mutated or not, and that failure
# stands.
class Evilution::Integration::Loading::FrozenNamespaces
  # Of the given names, those a mutant may yet freeze: the ones that are not a
  # frozen class or module now.
  def self.taken(names)
    new(names.reject { |name| frozen_namespace?(name) })
  end

  def self.frozen_namespace?(name)
    Object.const_defined?(name, false) && Object.const_get(name).frozen?
  end

  def initialize(unfrozen)
    @unfrozen = unfrozen
    freeze
  end

  NONE = new([])

  # Runs the block. When it raises FrozenError on a class the mutant froze,
  # removes that class's constant and runs the block once more.
  def recover
    yield
  rescue FrozenError => e
    name = frozen_since_taken(e)
    raise unless name

    put_aside(name)
    yield
  end

  private

  # A FrozenError raised by hand need not name what is frozen: asking it for
  # its receiver then raises ArgumentError.
  def frozen_since_taken(error)
    receiver = error.receiver
    @unfrozen.find { |name| Object.const_defined?(name, false) && Object.const_get(name).equal?(receiver) }
  rescue ArgumentError
    nil
  end

  def put_aside(name)
    parent_name, _, local_name = name.rpartition("::")
    parent = parent_name.empty? ? Object : Object.const_get(parent_name)
    parent.send(:remove_const, local_name)
  end
end
