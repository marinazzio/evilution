# frozen_string_literal: true

require "json"
require "evilution/reporter/json"
require "evilution/result/mutation_result"
require "evilution/result/summary"

RSpec.describe Evilution::Reporter::JSON do
  subject(:reporter) { described_class.new }

  let(:survived_mutation) do
    double(
      "Mutation",
      operator_name: "comparison_replacement",
      file_path: "lib/user.rb",
      line: 9,
      diff: "- x >= 10\n+ x > 10"
    )
  end

  let(:killed_mutation) do
    double(
      "Mutation",
      operator_name: "comparison_replacement",
      file_path: "lib/user.rb",
      line: 5,
      diff: "- x == 10\n+ x != 10"
    )
  end

  let(:survived_result) do
    Evilution::Result::MutationResult.new(
      mutation: survived_mutation,
      status: :survived,
      duration: 0.123
    )
  end

  let(:killed_result) do
    Evilution::Result::MutationResult.new(
      mutation: killed_mutation,
      status: :killed,
      duration: 0.456
    )
  end

  let(:summary) do
    Evilution::Result::Summary.new(
      results: [survived_result, killed_result],
      duration: 0.6
    )
  end

  describe "#call" do
    it "returns valid JSON" do
      output = reporter.call(summary)

      expect { JSON.parse(output) }.not_to raise_error
    end

    it "includes version" do
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["version"]).to eq(Evilution::VERSION)
    end

    it "includes summary stats" do
      parsed = JSON.parse(reporter.call(summary))
      stats = parsed["summary"]

      expect(stats["total"]).to eq(2)
      expect(stats["killed"]).to eq(1)
      expect(stats["survived"]).to eq(1)
      expect(stats["score"]).to eq(0.5)
    end

    it "includes survived mutations with details" do
      parsed = JSON.parse(reporter.call(summary))
      survived = parsed["survived"]

      expect(survived.length).to eq(1)
      expect(survived.first["operator"]).to eq("comparison_replacement")
      expect(survived.first["file"]).to eq("lib/user.rb")
      expect(survived.first["line"]).to eq(9)
      expect(survived.first["diff"]).to include(">= 10")
    end

    it "includes killed mutations" do
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["killed"].length).to eq(1)
      expect(parsed["killed"].first["status"]).to eq("killed")
    end

    it "handles empty results" do
      empty_summary = Evilution::Result::Summary.new(results: [], duration: 0.0)
      parsed = JSON.parse(reporter.call(empty_summary))

      expect(parsed["summary"]["total"]).to eq(0)
      expect(parsed["survived"]).to eq([])
      expect(parsed["killed"]).to eq([])
    end

    it "includes timestamp" do
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["timestamp"]).to match(/\d{4}-\d{2}-\d{2}T/)
    end

    it "rounds duration values" do
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["summary"]["duration"]).to eq(0.6)
      expect(parsed["killed"].first["duration"]).to eq(0.456)
    end
  end
end
