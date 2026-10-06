# frozen_string_literal: true

require "evilution/baseline"

RSpec.describe Evilution::Reporter::CLI::LineFormatters::BaselineNeutralizedNotice do
  subject(:formatter) { described_class.new }

  def example_failure
    Evilution::Baseline::ExampleFailure.new(
      id: "./spec/x_helper_spec.rb[1:1]", description: "XHelper greets", message: "NameError: nope"
    )
  end

  def spec_failure(spec_file, **)
    Evilution::Baseline::SpecFailure.new(spec_file: spec_file, **)
  end

  def neutralization(**)
    Evilution::Result::BaselineNeutralization.new(**)
  end

  def summary_with(*neutralizations)
    instance_double(Evilution::Result::Summary, baseline_neutralizations: neutralizations)
  end

  describe "#format" do
    it "returns nil when the baseline neutralized nothing" do
      expect(formatter.format(summary_with)).to be_nil
    end

    it "says how many survivors a red spec file turned neutral, and why it was red" do
      failure = spec_failure("spec/x_helper_spec.rb", examples: [example_failure], example_count: 1)
      summary = summary_with(neutralization(spec_file: "spec/x_helper_spec.rb", count: 24, failures: [failure]))

      expect(formatter.format(summary)).to eq(
        "! 24 survivors reclassified neutral because baseline failed for spec/x_helper_spec.rb; " \
        "they may be real gaps.\n    " \
        "./spec/x_helper_spec.rb[1:1] XHelper greets -- NameError: nope"
      )
    end

    it "speaks of a single survivor in the singular" do
      failure = spec_failure("spec/a_spec.rb", error: "timed out after 30s")
      summary = summary_with(neutralization(spec_file: "spec/a_spec.rb", count: 1, failures: [failure]))

      expect(formatter.format(summary)).to eq(
        "! 1 survivor reclassified neutral because baseline failed for spec/a_spec.rb; it may be a real gap.\n    " \
        "timed out after 30s"
      )
    end

    it "names the spec file even when no failure detail came with it" do
      summary = summary_with(neutralization(spec_file: "spec/a_spec.rb", count: 2, failures: []))

      expect(formatter.format(summary)).to eq(
        "! 2 survivors reclassified neutral because baseline failed for spec/a_spec.rb; they may be real gaps."
      )
    end

    it "names every red spec file of a run given explicit spec files, each above its own detail" do
      failures = [spec_failure("spec/a_spec.rb", error: "boom"), spec_failure("spec/b_spec.rb", error: "bang")]
      summary = summary_with(neutralization(spec_file: nil, count: 3, failures: failures))

      expect(formatter.format(summary)).to eq(
        "! 3 survivors reclassified neutral because baseline failed for spec/a_spec.rb, spec/b_spec.rb; " \
        "they may be real gaps.\n    " \
        "spec/a_spec.rb:\n      boom\n    " \
        "spec/b_spec.rb:\n      bang"
      )
    end

    it "still reports a neutralization that names no spec file at all" do
      summary = summary_with(neutralization(spec_file: nil, count: 3, failures: []))

      expect(formatter.format(summary)).to eq(
        "! 3 survivors reclassified neutral because baseline failed; they may be real gaps."
      )
    end

    it "reports each red spec file on its own line" do
      summary = summary_with(
        neutralization(spec_file: "spec/a_spec.rb", count: 2, failures: []),
        neutralization(spec_file: "spec/b_spec.rb", count: 5, failures: [])
      )

      expect(formatter.format(summary).lines.map(&:chomp)).to eq(
        [
          "! 2 survivors reclassified neutral because baseline failed for spec/a_spec.rb; they may be real gaps.",
          "! 5 survivors reclassified neutral because baseline failed for spec/b_spec.rb; they may be real gaps."
        ]
      )
    end
  end
end
