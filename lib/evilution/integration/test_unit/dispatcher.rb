# frozen_string_literal: true

require "stringio"
require_relative "../test_unit"

# Builds a Test::Unit::TestSuite from a list of TestCase subclasses and runs
# it via the console runner with output captured to a StringIO. Owning this
# responsibility separately keeps the runner library require + suite assembly
# in one place — used by both the baseline path (Evilution::Integration::TestUnit
# .run_baseline_test_file) and the per-mutation path (#run_tests).
module Evilution::Integration::TestUnit::Dispatcher
  module_function

  def call(test_case_classes, name: "evilution")
    require "test/unit/ui/console/testrunner"
    suite = ::Test::Unit::TestSuite.new(name)
    test_case_classes.each { |klass| suite << klass.suite }
    out = StringIO.new
    runner = ::Test::Unit::UI::Console::TestRunner.new(suite, output: out)
    runner.start
  end

  def test_method_count(test_case_classes)
    test_case_classes.sum { |klass| klass.suite.tests.length }
  end
end
