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

  # on_fault, when given, is called with each fault the run records and the
  # run's Test::Unit::TestResult, which it may stop. The runner returns that
  # result whether or not the run was stopped.
  def call(test_case_classes, name: "evilution", on_fault: nil)
    require "test/unit/ui/console/testrunner"
    suite = ::Test::Unit::TestSuite.new(name)
    test_case_classes.each { |klass| suite << klass.suite }
    out = StringIO.new
    runner = ::Test::Unit::UI::Console::TestRunner.new(suite, output: out)
    runner.listeners << FaultListener.new(on_fault) unless on_fault.nil?
    runner.start
  end

  def test_method_count(test_case_classes)
    test_case_classes.sum { |klass| klass.suite.tests.length }
  end

  # Attached to the runner's mediator. The run's result exists only once the
  # mediator has started it, and `result.stop` works only from then on: the
  # mediator sets the tag it throws to just before announcing the start.
  class FaultListener
    def initialize(on_fault)
      @on_fault = on_fault
    end

    def attach_to_mediator(mediator)
      mediator.add_listener(::Test::Unit::UI::TestRunnerMediator::STARTED) do |result|
        result.add_listener(::Test::Unit::TestResult::FAULT) { |fault| @on_fault.call(fault, result) }
      end
    end
  end
end
