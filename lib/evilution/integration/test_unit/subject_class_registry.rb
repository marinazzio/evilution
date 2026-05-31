# frozen_string_literal: true

require_relative "../test_unit"

# Tracks Test::Unit::TestCase descendants in the host process. Test::Unit has
# no public registry-clear method analogous to Minitest::Runnable.runnables;
# the integration scopes each dispatch to classes that appeared during *this*
# round by diffing the descendant set before and after #load. Keeping that
# responsibility in its own object makes it cheap to stub in tests and lets
# the integration's main class read as orchestration.
module Evilution::Integration::TestUnit::SubjectClassRegistry
  module_function

  def descendants
    return [] unless defined?(::Test::Unit::TestCase)

    ObjectSpace.each_object(Class).select { |c| c < ::Test::Unit::TestCase }
  end

  # Yields, captures the descendant set before/after, and returns the diff.
  def newly_loaded
    before = descendants
    yield
    descendants - before
  end
end
