# frozen_string_literal: true

require "stringio"
require_relative "base"

require_relative "../integration"

class Evilution::Integration::TestUnit < Evilution::Integration::Base
  def self.baseline_runner
    ->(test_file) { run_baseline_test_file(test_file) }
  end

  def self.run_baseline_test_file(test_file)
    require "test-unit"
    require "stringio"
    stub_autorun!
    before = test_case_subclasses
    baseline_test_files(test_file).each { |f| load(File.expand_path(f)) }
    new_classes = test_case_subclasses - before
    run_baseline_test_unit(new_classes)
  end

  def self.baseline_test_files(test_file)
    File.directory?(test_file) ? Dir.glob(File.join(test_file, "**/*_test.rb")) : [test_file]
  end

  # Build a suite from explicitly-loaded test classes and dispatch via the
  # console runner with output piped to a StringIO. Scoping by loaded class
  # (rather than letting AutoRunner discover ObjectSpace) keeps stale test
  # classes from previous baseline calls out of the run — important for tests
  # that exercise the loader repeatedly, and harmless in production where the
  # baseline runs once per fork. need_auto_run= is flipped to false so
  # test-unit's at_exit hook never fires when evilution exits.
  def self.run_baseline_test_unit(test_case_classes)
    require "test/unit/ui/console/testrunner"
    suite = Test::Unit::TestSuite.new("evilution baseline")
    test_case_classes.each { |klass| suite << klass.suite }
    out = StringIO.new
    runner = Test::Unit::UI::Console::TestRunner.new(suite, output: out)
    result = runner.start
    result.passed?
  end

  def self.test_case_subclasses
    ObjectSpace.each_object(Class).select { |c| c < Test::Unit::TestCase }
  end

  # User code that `require "test-unit"` (or "test/unit") installs an at_exit
  # hook that calls Test::Unit::AutoRunner.run when need_auto_run? is true.
  # At evilution process exit ARGV still holds evilution flags
  # (--integration, --spec, ...) and the runner prints a misleading banner.
  # Flipping need_auto_run = false here prevents the handler from firing.
  def self.stub_autorun!
    return unless defined?(Test::Unit::AutoRunner)

    Test::Unit::AutoRunner.need_auto_run = false
  end

  private

  def ensure_framework_loaded
    return if @test_unit_loaded

    require "test-unit"
    self.class.stub_autorun!
    @test_unit_loaded = true
  rescue LoadError => e
    raise Evilution::Error, "test-unit is required but not available: #{e.message}"
  end
end
