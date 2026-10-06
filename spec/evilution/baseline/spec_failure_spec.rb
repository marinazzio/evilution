# frozen_string_literal: true

require "evilution/baseline"

RSpec.describe Evilution::Baseline::SpecFailure do
  let(:report) do
    {
      passed: false,
      failure_count: 3,
      failures: [{ id: "./spec/a_spec.rb[1:1]", description: "A works", message: "boom" }],
      error: nil
    }
  end

  describe ".from_report" do
    subject(:failure) { described_class.from_report("spec/a_spec.rb", report) }

    it "names the spec file" do
      expect(failure.spec_file).to eq("spec/a_spec.rb")
    end

    it "builds the failing examples" do
      expect(failure.examples).to eq(
        [Evilution::Baseline::ExampleFailure.new(id: "./spec/a_spec.rb[1:1]", description: "A works", message: "boom")]
      )
    end

    it "keeps the total number of failing examples" do
      expect(failure.example_count).to eq(3)
    end

    it "carries the error" do
      expect(described_class.from_report("spec/a_spec.rb", report.merge(error: "bad")).error).to eq("bad")
    end

    it "tolerates a report holding only the pass flag" do
      bare = described_class.from_report("spec/a_spec.rb", { passed: false })

      expect(bare).to eq(described_class.new(spec_file: "spec/a_spec.rb"))
    end

    it "falls back to the listed failures when the count is missing" do
      listed = described_class.from_report("spec/a_spec.rb", report.except(:failure_count))

      expect(listed.example_count).to eq(1)
    end
  end

  describe ".new" do
    it "defaults to no detail" do
      failure = described_class.new(spec_file: "spec/a_spec.rb")

      expect(failure.examples).to eq([])
      expect(failure.example_count).to eq(0)
      expect(failure.error).to be_nil
    end
  end

  describe "#to_h" do
    it "is a plain hash ready for JSON" do
      failure = described_class.from_report("spec/a_spec.rb", report.merge(error: "bad"))

      expect(failure.to_h).to eq(
        spec_file: "spec/a_spec.rb",
        error: "bad",
        failing_examples: 3,
        examples: [{ id: "./spec/a_spec.rb[1:1]", description: "A works", message: "boom" }]
      )
    end
  end
end
