# frozen_string_literal: true

require "evilution/integration/test_unit_crash_detector"

RSpec.describe Evilution::Integration::TestUnitCrashDetector do
  let(:detector) { described_class.new }

  before do
    require "test-unit"
    require "test/unit/failure"
    require "test/unit/error"
    require "test/unit/testresult"
  end

  def assertion_fault(message: "1 expected got 2")
    Test::Unit::Failure.new("test_demo", ["spec.rb:1"], message)
  end

  def error_fault(exception_class: RuntimeError, message: "boom")
    Test::Unit::Error.new("test_demo", exception_class.new(message))
  end

  describe "#passed?" do
    it "is true with no recorded faults" do
      expect(detector.passed?).to be true
    end

    it "is false once any fault is recorded" do
      detector.record(assertion_fault)

      expect(detector.passed?).to be false
    end
  end

  describe "#record" do
    it "counts a Test::Unit::Failure as an assertion failure" do
      detector.record(assertion_fault)

      expect(detector.assertion_failure?).to be true
      expect(detector.crashed?).to be false
    end

    it "captures a Test::Unit::Error as a crash" do
      detector.record(error_fault(exception_class: ArgumentError, message: "bad"))

      expect(detector.crashed?).to be true
      expect(detector.assertion_failure?).to be false
    end

    it "ignores unknown fault classes (does not raise, does not record)" do
      unknown = double("Unknown::Fault")

      expect { detector.record(unknown) }.not_to raise_error
      expect(detector.crashed?).to be false
      expect(detector.assertion_failure?).to be false
    end
  end

  describe "#only_crashes?" do
    it "is false on a clean detector" do
      expect(detector.only_crashes?).to be false
    end

    it "is true when only Test::Unit::Error faults were recorded" do
      detector.record(error_fault)
      detector.record(error_fault(exception_class: TypeError))

      expect(detector.only_crashes?).to be true
    end

    it "is false when a Test::Unit::Failure is mixed in with crashes" do
      detector.record(error_fault)
      detector.record(assertion_fault)

      expect(detector.only_crashes?).to be false
    end
  end

  describe "#unique_crash_classes" do
    it "returns the unique set of exception class names from recorded crashes" do
      detector.record(error_fault(exception_class: RuntimeError))
      detector.record(error_fault(exception_class: ArgumentError))
      detector.record(error_fault(exception_class: RuntimeError))

      expect(detector.unique_crash_classes).to contain_exactly("RuntimeError", "ArgumentError")
    end

    it "returns an empty array when no crashes were recorded" do
      detector.record(assertion_fault)

      expect(detector.unique_crash_classes).to eq([])
    end
  end

  describe "#crash_summary" do
    it "is nil when no crashes were recorded" do
      detector.record(assertion_fault)

      expect(detector.crash_summary).to be_nil
    end

    it "formats a single crash as 'ClassName (1 crash)'" do
      detector.record(error_fault(exception_class: RuntimeError))

      expect(detector.crash_summary).to eq("RuntimeError (1 crash)")
    end

    it "formats multiple crashes as 'ClassA, ClassB (N crashes)'" do
      detector.record(error_fault(exception_class: RuntimeError))
      detector.record(error_fault(exception_class: ArgumentError))

      expect(detector.crash_summary).to eq("RuntimeError, ArgumentError (2 crashes)")
    end
  end

  describe "#reset" do
    it "clears recorded crashes and assertion failures" do
      detector.record(error_fault)
      detector.record(assertion_fault)

      detector.reset

      expect(detector.passed?).to be true
      expect(detector.crashed?).to be false
      expect(detector.assertion_failure?).to be false
    end
  end

  describe "#attach" do
    it "subscribes to FAULT notifications on a Test::Unit::TestResult so detector.record is called" do
      result = Test::Unit::TestResult.new

      detector.attach(result)
      result.notify_listeners(Test::Unit::TestResult::FAULT, error_fault(exception_class: RuntimeError))

      expect(detector.crashed?).to be true
    end
  end
end
