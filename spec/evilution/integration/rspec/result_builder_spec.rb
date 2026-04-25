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
  end
end
