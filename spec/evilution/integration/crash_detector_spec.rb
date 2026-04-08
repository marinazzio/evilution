# frozen_string_literal: true

require "evilution/integration/crash_detector"

RSpec.describe Evilution::Integration::CrashDetector do
  subject(:detector) { described_class.new(StringIO.new) }

  def make_notification(exception)
    example = double("Example", exception: exception)
    double("Notification", example: example)
  end

  describe "#example_failed" do
    it "records assertion failures" do
      notification = make_notification(
        RSpec::Expectations::ExpectationNotMetError.new("expected x to eq y")
      )

      detector.example_failed(notification)

      expect(detector).to have_assertion_failure
      expect(detector).not_to have_crash
    end

    it "records runtime crashes" do
      notification = make_notification(NoMethodError.new("undefined method 'foo'"))

      detector.example_failed(notification)

      expect(detector).to have_crash
      expect(detector).not_to have_assertion_failure
    end

    it "records both assertion failures and crashes separately" do
      detector.example_failed(make_notification(
                                RSpec::Expectations::ExpectationNotMetError.new("fail")
                              ))
      detector.example_failed(make_notification(NoMethodError.new("crash")))

      expect(detector).to have_assertion_failure
      expect(detector).to have_crash
    end

    it "treats RSpec::Core::MultipleExceptionError as crash" do
      multi_error = RSpec::Core::MultipleExceptionError.new(
        NoMethodError.new("foo"), NameError.new("bar")
      )
      detector.example_failed(make_notification(multi_error))

      expect(detector).to have_crash
    end

    it "treats SystemStackError as crash" do
      detector.example_failed(make_notification(SystemStackError.new("stack overflow")))

      expect(detector).to have_crash
    end
  end

  describe "#only_crashes?" do
    it "returns true when all failures are crashes" do
      detector.example_failed(make_notification(NoMethodError.new("crash")))
      detector.example_failed(make_notification(TypeError.new("wrong type")))

      expect(detector).to be_only_crashes
    end

    it "returns false when there are assertion failures" do
      detector.example_failed(make_notification(
                                RSpec::Expectations::ExpectationNotMetError.new("fail")
                              ))
      detector.example_failed(make_notification(NoMethodError.new("crash")))

      expect(detector).not_to be_only_crashes
    end

    it "returns false when no failures recorded" do
      expect(detector).not_to be_only_crashes
    end
  end

  describe "#crash_summary" do
    it "returns a summary of crash exceptions" do
      detector.example_failed(make_notification(NoMethodError.new("undefined method 'foo'")))
      detector.example_failed(make_notification(TypeError.new("wrong type")))

      summary = detector.crash_summary

      expect(summary).to include("NoMethodError")
      expect(summary).to include("TypeError")
    end

    it "returns nil when no crashes" do
      expect(detector.crash_summary).to be_nil
    end
  end
end
