# frozen_string_literal: true

require "stringio"
require "evilution/integration/crash_detector"
require "evilution/integration/stop_policy"
require "evilution/integration/known_failures"

RSpec.describe Evilution::Integration::CrashDetector do
  subject(:detector) { described_class.new(StringIO.new) }

  def make_notification(exception, scoped_id: "1:1")
    example = double("Example", exception: exception,
                                metadata: { rerun_file_path: "./spec/gate_spec.rb", scoped_id: scoped_id })
    double("Notification", example: example)
  end

  describe "#example_failed" do
    it "records assertion failures" do
      notification = make_notification(
        RSpec::Expectations::ExpectationNotMetError.new("expected x to eq y")
      )

      detector.example_failed(notification)

      expect(detector).to be_assertion_failure
      expect(detector).not_to be_crashed
    end

    it "records runtime crashes" do
      notification = make_notification(NoMethodError.new("undefined method 'foo'"))

      detector.example_failed(notification)

      expect(detector).to be_crashed
      expect(detector).not_to be_assertion_failure
    end

    it "records both assertion failures and crashes separately" do
      detector.example_failed(make_notification(
                                RSpec::Expectations::ExpectationNotMetError.new("fail")
                              ))
      detector.example_failed(make_notification(NoMethodError.new("crash")))

      expect(detector).to be_assertion_failure
      expect(detector).to be_crashed
    end

    it "treats RSpec::Core::MultipleExceptionError as crash" do
      multi_error = RSpec::Core::MultipleExceptionError.new(
        NoMethodError.new("foo"), NameError.new("bar")
      )
      detector.example_failed(make_notification(multi_error))

      expect(detector).to be_crashed
    end

    it "treats SystemStackError as crash" do
      detector.example_failed(make_notification(SystemStackError.new("stack overflow")))

      expect(detector).to be_crashed
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

  # The run stops at its first decisive failure: RSpec checks
  # RSpec.world.wants_to_quit before every example and skips the rest once it
  # is set.
  describe "stopping the run" do
    let(:known_id) { "#{File.expand_path("spec/gate_spec.rb")}[1:1]" }
    let(:policy) do
      Evilution::Integration::StopPolicy.new(
        enabled: true, known_failures: Evilution::Integration::KnownFailures.new([known_id])
      )
    end
    let(:assertion) { RSpec::Expectations::ExpectationNotMetError.new("expected x to eq y") }

    around do |example|
      before = RSpec.world.wants_to_quit
      RSpec.world.wants_to_quit = false
      example.run
    ensure
      RSpec.world.wants_to_quit = before
    end

    it "asks RSpec to stop at the first assertion failure" do
      detector.policy = policy

      detector.example_failed(make_notification(assertion, scoped_id: "1:2"))

      expect(RSpec.world.wants_to_quit).to be(true)
      expect(detector).to be_assertion_failure
    end

    it "asks RSpec to stop at the first crash that is not the infrastructure's" do
      detector.policy = policy

      detector.example_failed(make_notification(NoMethodError.new("crash"), scoped_id: "1:2"))

      expect(RSpec.world.wants_to_quit).to be(true)
      expect(detector).to be_crashed
    end

    it "lets the run go on past an example the baseline already saw failing" do
      detector.policy = policy

      detector.example_failed(make_notification(assertion, scoped_id: "1:1"))

      expect(RSpec.world.wants_to_quit).to be(false)
      expect(detector).to be_assertion_failure
    end

    it "lets the run go on past a crash of the test infrastructure" do
      stub_const("SQLite3::BusyException", Class.new(StandardError))
      detector.policy = policy

      detector.example_failed(make_notification(SQLite3::BusyException.new("database is locked"), scoped_id: "1:2"))

      expect(RSpec.world.wants_to_quit).to be(false)
      expect(detector).to be_crashed
    end

    it "stops at a decisive failure that comes after ones that are not" do
      stub_const("SQLite3::BusyException", Class.new(StandardError))
      detector.policy = policy

      detector.example_failed(make_notification(assertion, scoped_id: "1:1"))
      detector.example_failed(make_notification(SQLite3::BusyException.new("locked"), scoped_id: "1:2"))
      expect(RSpec.world.wants_to_quit).to be(false)

      detector.example_failed(make_notification(assertion, scoped_id: "1:3"))
      expect(RSpec.world.wants_to_quit).to be(true)
    end

    it "never stops a run without a policy" do
      detector.example_failed(make_notification(assertion, scoped_id: "1:2"))
      detector.example_failed(make_notification(NoMethodError.new("crash"), scoped_id: "1:3"))

      expect(RSpec.world.wants_to_quit).to be(false)
    end

    it "never stops a run under the disabled policy" do
      detector.policy = Evilution::Integration::StopPolicy::DISABLED

      detector.example_failed(make_notification(assertion, scoped_id: "1:2"))

      expect(RSpec.world.wants_to_quit).to be(false)
    end
  end

  describe ".register_with_rspec" do
    it "registers the class with RSpec's formatter registry for :example_failed" do
      expect(RSpec::Core::Formatters).to receive(:register)
        .with(described_class, :example_failed)

      described_class.register_with_rspec
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

    it "joins distinct crash class names with a comma and space" do
      detector.example_failed(make_notification(NoMethodError.new("a")))
      detector.example_failed(make_notification(TypeError.new("b")))

      expect(detector.crash_summary).to start_with("NoMethodError, TypeError (")
    end

    it "reports the crash count, not the crash array, in the summary" do
      3.times { detector.example_failed(make_notification(NoMethodError.new("x"))) }

      expect(detector.crash_summary).to eq("NoMethodError (3 crashes)")
    end

    it "uses the singular noun 'crash' for exactly one crash" do
      detector.example_failed(make_notification(NoMethodError.new("only one")))

      expect(detector.crash_summary).to eq("NoMethodError (1 crash)")
    end

    it "uses the plural noun 'crashes' for more than one crash" do
      detector.example_failed(make_notification(NoMethodError.new("a")))
      detector.example_failed(make_notification(NoMethodError.new("b")))

      expect(detector.crash_summary).to eq("NoMethodError (2 crashes)")
    end
  end

  describe "#unique_crash_classes" do
    it "returns empty array when no crashes recorded" do
      expect(detector.unique_crash_classes).to eq([])
    end

    it "returns a single class name when all crashes share a class" do
      3.times { detector.example_failed(make_notification(NoMethodError.new("foo"))) }

      expect(detector.unique_crash_classes).to eq(["NoMethodError"])
    end

    it "returns all distinct classes preserving first-seen order" do
      detector.example_failed(make_notification(TypeError.new("a")))
      detector.example_failed(make_notification(NoMethodError.new("b")))
      detector.example_failed(make_notification(TypeError.new("c")))

      expect(detector.unique_crash_classes).to eq(%w[TypeError NoMethodError])
    end
  end
end
