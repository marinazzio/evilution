# frozen_string_literal: true

require "json"
require "evilution/reporter/json"
require "evilution/reporter/cli"
require "evilution/result/mutation_result"
require "evilution/result/summary"

RSpec.describe "Reporter memory stats" do
  let(:subject_obj) { double("Subject", name: "User#valid?") }

  let(:mutation) do
    double("Mutation",
           operator_name: "comparison_replacement",
           file_path: "lib/user.rb",
           line: 9,
           diff: "- x >= 10\n+ x > 10",
           unified_diff: nil,
           subject: subject_obj,
           unparseable?: false)
  end

  let(:result_with_rss) do
    Evilution::Result::MutationResult.new(
      mutation: mutation, status: :killed, duration: 0.1,
      child_rss_kb: 51_200
    )
  end

  let(:result_with_delta) do
    Evilution::Result::MutationResult.new(
      mutation: mutation, status: :survived, duration: 0.2,
      memory_delta_kb: 2400
    )
  end

  let(:result_without_memory) do
    Evilution::Result::MutationResult.new(
      mutation: mutation, status: :killed, duration: 0.1
    )
  end

  describe Evilution::Result::Summary do
    it "computes peak_memory_mb from child_rss_kb values" do
      summary = described_class.new(
        results: [result_with_rss, result_without_memory],
        duration: 1.0
      )

      expect(summary.peak_memory_mb).to eq(50.0)
    end

    it "returns nil peak_memory_mb when no results have child_rss_kb" do
      summary = described_class.new(
        results: [result_without_memory],
        duration: 1.0
      )

      expect(summary.peak_memory_mb).to be_nil
    end

    it "returns nil peak_memory_mb for empty results" do
      summary = described_class.new(results: [], duration: 0.0)

      expect(summary.peak_memory_mb).to be_nil
    end
  end

  describe Evilution::Reporter::JSON do
    subject(:reporter) { described_class.new }

    it "includes peak_memory_mb in summary when available" do
      summary = Evilution::Result::Summary.new(
        results: [result_with_rss], duration: 1.0
      )
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["summary"]["peak_memory_mb"]).to eq(50.0)
    end

    it "omits peak_memory_mb from summary when not available" do
      summary = Evilution::Result::Summary.new(
        results: [result_without_memory], duration: 1.0
      )
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["summary"]).not_to have_key("peak_memory_mb")
    end

    it "includes child_rss_kb in mutation detail when available" do
      summary = Evilution::Result::Summary.new(
        results: [result_with_rss], duration: 1.0
      )
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["killed"].first["child_rss_kb"]).to eq(51_200)
    end

    it "includes memory_delta_kb in mutation detail when available" do
      summary = Evilution::Result::Summary.new(
        results: [result_with_delta], duration: 1.0
      )
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["survived"].first["memory_delta_kb"]).to eq(2400)
    end

    it "omits memory fields from mutation detail when not available" do
      summary = Evilution::Result::Summary.new(
        results: [result_without_memory], duration: 1.0
      )
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["killed"].first).not_to have_key("child_rss_kb")
      expect(parsed["killed"].first).not_to have_key("memory_delta_kb")
    end
  end

  describe Evilution::Reporter::CLI do
    subject(:reporter) { described_class.new }

    it "includes peak memory line when available" do
      summary = Evilution::Result::Summary.new(
        results: [result_with_rss], duration: 1.0
      )
      output = reporter.call(summary)

      expect(output).to include("Peak memory: 50.0 MB")
    end

    it "does not include peak memory line when not available" do
      summary = Evilution::Result::Summary.new(
        results: [result_without_memory], duration: 1.0
      )
      output = reporter.call(summary)

      expect(output).not_to include("Peak memory")
    end
  end
end
