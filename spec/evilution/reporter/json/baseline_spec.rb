# frozen_string_literal: true

require "evilution/baseline"

RSpec.describe Evilution::Reporter::JSON::Baseline do
  subject(:fields) { described_class.new.call(summary) }

  let(:failure) { Evilution::Baseline::SpecFailure.new(spec_file: "spec/a_spec.rb", error: "boom") }

  def summary_with(neutralized:, failures:)
    instance_double(Evilution::Result::Summary, baseline_neutralized: neutralized, baseline_failures: failures)
  end

  context "when the baseline was green" do
    let(:summary) { summary_with(neutralized: 0, failures: []) }

    it "adds nothing" do
      expect(fields).to eq({})
    end
  end

  context "when a red spec file neutralized survivors" do
    let(:summary) { summary_with(neutralized: 3, failures: [failure]) }

    it "gives the count and the failure" do
      expect(fields).to eq(
        baseline_neutralized: 3,
        baseline_failures: [{ spec_file: "spec/a_spec.rb", error: "boom", failing_examples: 0, examples: [] }]
      )
    end
  end

  context "when a red spec file neutralized nothing" do
    let(:summary) { summary_with(neutralized: 0, failures: [failure]) }

    it "gives the failure alone" do
      expect(fields.keys).to eq([:baseline_failures])
    end
  end

  context "when survivors were neutralized without recorded failures" do
    let(:summary) { summary_with(neutralized: 1, failures: []) }

    it "gives the count alone" do
      expect(fields).to eq(baseline_neutralized: 1)
    end
  end
end
