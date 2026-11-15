# frozen_string_literal: true

require_relative "../test_unit"
require_relative "../../class_tree"

# Tracks Test::Unit::TestCase descendants in the host process. Test::Unit has
# no public registry-clear method analogous to Minitest::Runnable.runnables;
# the integration scopes each dispatch to classes that appeared during *this*
# round by diffing the descendant set before and after #load. Keeping that
# responsibility in its own object makes it cheap to stub in tests and lets
# the integration's main class read as orchestration.
#
# The descendants come from the class tree, not from a walk of the heap: a
# mutation process loads its test files afresh, and walking every object
# before and after each load is a cost per mutation.
module Evilution::Integration::TestUnit::SubjectClassRegistry
  module_function

  def descendants
    return [] unless defined?(::Test::Unit::TestCase)

    Evilution::ClassTree.descendants(::Test::Unit::TestCase)
  end

  # Yields, captures the descendant set before/after, and returns the diff.
  def newly_loaded
    before = descendants
    yield
    descendants - before
  end
end
