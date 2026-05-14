# frozen_string_literal: true

require "spec_helper"
require "evilution/integration/rspec/result_builder"

RSpec.describe Evilution::Integration::RSpec::ResultBuilder do
  let(:builder) { described_class.new }
  let(:mutation) { instance_double("Mutation", file_path: "lib/foo.rb") }

  describe "#unresolved" do
    it "returns the unresolved hash with file_path-aware error and command" do
      result = builder.unresolved(mutation)
      expect(result).to eq({
                             passed: false,
                             unresolved: true,
                             error: "no matching spec resolved for lib/foo.rb",
                             test_command: "rspec (skipped: no spec resolved for lib/foo.rb)"
                           })
    end
  end

  describe "#unresolved_example" do
    it "returns the unresolved-example hash with file_path-aware error and command" do
      result = builder.unresolved_example(mutation)
      expect(result).to eq({
                             passed: false,
                             unresolved: true,
                             error: "no matching example found for lib/foo.rb",
                             test_command: "rspec (skipped: no matching example for lib/foo.rb)"
                           })
    end
  end

  describe "#from_run" do
    let(:detector) do
      instance_double("CrashDetector", only_crashes?: false, unique_crash_classes: [], crash_summary: "")
    end

    it "returns pass hash when status is zero" do
      expect(builder.from_run(0, "rspec args", detector))
        .to eq({ passed: true, test_command: "rspec args" })
    end

    it "returns crash hash when status nonzero AND only_crashes?, with single error_class" do
      allow(detector).to receive(:only_crashes?).and_return(true)
      allow(detector).to receive(:unique_crash_classes).and_return(["RuntimeError"])
      allow(detector).to receive(:crash_summary).and_return("RuntimeError x1")

      result = builder.from_run(1, "rspec args", detector)

      expect(result).to eq({
                             passed: false,
                             test_crashed: true,
                             error: "test crashes: RuntimeError x1",
                             error_class: "RuntimeError",
                             test_command: "rspec args"
                           })
    end

    it "returns crash hash WITHOUT error_class when multiple unique_crash_classes" do
      allow(detector).to receive(:only_crashes?).and_return(true)
      allow(detector).to receive(:unique_crash_classes).and_return(%w[RuntimeError NoMethodError])
      allow(detector).to receive(:crash_summary).and_return("multi")

      result = builder.from_run(1, "rspec args", detector)

      expect(result[:test_crashed]).to be true
      expect(result[:error_class]).to be_nil
    end

    it "returns plain fail hash when status nonzero AND not only_crashes?" do
      result = builder.from_run(1, "rspec args", detector)
      expect(result).to eq({ passed: false, test_command: "rspec args" })
    end

    # Bug B (EV-720r): user reported all mutations marked `killed=100%` on
    # macOS Rails. Root cause is classify_status defaulting to :killed for any
    # nonzero RSpec exit. If RSpec returns nonzero because it loaded ZERO
    # examples (spec file failed to load, --spec ignored, fail_if_no_examples
    # active, etc.), there is no evidence the mutation was caught — calling
    # that "killed" silently produces wrong scores. Surface it as :error.
    context "when status nonzero AND zero examples loaded" do
      it "returns an error hash (so classify_status reports :error, not :killed)" do
        result = builder.from_run(2, "rspec args", detector, examples_loaded: 0)

        expect(result[:passed]).to be false
        expect(result[:error]).to match(/0 examples|no examples ran/i)
        expect(result[:test_command]).to eq("rspec args")
      end

      it "still surfaces crashes when only_crashes? is true, even with 0 examples" do
        # Crash signal is stronger than the zero-examples heuristic; keep
        # current behavior.
        allow(detector).to receive(:only_crashes?).and_return(true)
        allow(detector).to receive(:unique_crash_classes).and_return(["LoadError"])
        allow(detector).to receive(:crash_summary).and_return("LoadError x1")

        result = builder.from_run(1, "rspec args", detector, examples_loaded: 0)

        expect(result[:test_crashed]).to be true
        expect(result[:error_class]).to eq("LoadError")
      end
    end

    it "keeps plain fail behavior when examples_loaded is positive" do
      result = builder.from_run(1, "rspec args", detector, examples_loaded: 3)
      expect(result).to eq({ passed: false, test_command: "rspec args" })
    end

    it "keeps plain fail behavior when examples_loaded is nil (back-compat)" do
      result = builder.from_run(1, "rspec args", detector)
      expect(result).to eq({ passed: false, test_command: "rspec args" })
    end
  end
end
