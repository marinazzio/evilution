# frozen_string_literal: true

require "minitest"
require "evilution/integration/minitest_crash_detector"

RSpec.describe Evilution::Integration::MinitestCrashDetector do
  subject(:detector) { described_class.new }

  describe "#record" do
    it "tracks assertion failures" do
      result = Minitest::Result.new("test_foo")
      result.failures << Minitest::Assertion.new("expected true")

      detector.record(result)

      expect(detector).to have_assertion_failure
      expect(detector).not_to have_crash
    end

    it "tracks unexpected errors as crashes" do
      result = Minitest::Result.new("test_foo")
      result.failures << Minitest::UnexpectedError.new(RuntimeError.new("boom"))

      detector.record(result)

      expect(detector).to have_crash
      expect(detector).not_to have_assertion_failure
    end

    it "ignores passing results" do
      result = Minitest::Result.new("test_foo")

      detector.record(result)

      expect(detector).not_to have_crash
      expect(detector).not_to have_assertion_failure
    end
  end

  describe "#only_crashes?" do
    it "returns true when only crashes exist" do
      result = Minitest::Result.new("test_foo")
      result.failures << Minitest::UnexpectedError.new(NoMethodError.new("undefined"))

      detector.record(result)

      expect(detector.only_crashes?).to be true
    end

    it "returns false when assertion failures exist alongside crashes" do
      crash_result = Minitest::Result.new("test_foo")
      crash_result.failures << Minitest::UnexpectedError.new(RuntimeError.new("boom"))

      assertion_result = Minitest::Result.new("test_bar")
      assertion_result.failures << Minitest::Assertion.new("expected true")

      detector.record(crash_result)
      detector.record(assertion_result)

      expect(detector.only_crashes?).to be false
    end

    it "returns false when no failures exist" do
      expect(detector.only_crashes?).to be false
    end
  end

  describe "#crash_summary" do
    it "returns nil when no crashes" do
      expect(detector.crash_summary).to be_nil
    end

    it "returns summary with exception class and count" do
      result = Minitest::Result.new("test_foo")
      result.failures << Minitest::UnexpectedError.new(NoMethodError.new("undefined"))

      detector.record(result)

      expect(detector.crash_summary).to include("NoMethodError")
      expect(detector.crash_summary).to include("1 crash")
    end

    it "deduplicates exception types" do
      2.times do
        result = Minitest::Result.new("test_foo")
        result.failures << Minitest::UnexpectedError.new(RuntimeError.new("boom"))
        detector.record(result)
      end

      expect(detector.crash_summary).to include("RuntimeError")
      expect(detector.crash_summary).to include("2 crashes")
    end
  end

  describe "#unique_crash_classes" do
    it "returns empty array when no crashes" do
      expect(detector.unique_crash_classes).to eq([])
    end

    it "returns single class when all crashes share a class" do
      3.times do |i|
        r = Minitest::Result.new("t#{i}")
        r.failures << Minitest::UnexpectedError.new(RuntimeError.new("boom"))
        detector.record(r)
      end

      expect(detector.unique_crash_classes).to eq(["RuntimeError"])
    end

    it "returns distinct classes preserving first-seen order" do
      r1 = Minitest::Result.new("t1")
      r1.failures << Minitest::UnexpectedError.new(TypeError.new("a"))
      r2 = Minitest::Result.new("t2")
      r2.failures << Minitest::UnexpectedError.new(NoMethodError.new("b"))
      r3 = Minitest::Result.new("t3")
      r3.failures << Minitest::UnexpectedError.new(TypeError.new("c"))
      detector.record(r1)
      detector.record(r2)
      detector.record(r3)

      expect(detector.unique_crash_classes).to eq(%w[TypeError NoMethodError])
    end
  end

  describe "#reset" do
    it "clears all tracked state" do
      result = Minitest::Result.new("test_foo")
      result.failures << Minitest::UnexpectedError.new(RuntimeError.new("boom"))
      detector.record(result)

      detector.reset

      expect(detector).not_to have_crash
      expect(detector).not_to have_assertion_failure
      expect(detector.crash_summary).to be_nil
    end
  end
end
