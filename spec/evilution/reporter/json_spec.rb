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
      expect(survived.first["suggestion"]).to eq(
        "Add a test for the boundary condition where the comparison operand equals the threshold exactly"
      )
    end

    it "includes killed mutations" do
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["killed"].length).to eq(1)
      expect(parsed["killed"].first["status"]).to eq("killed")
    end

    it "does not include suggestion for killed mutations" do
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["killed"].first).not_to have_key("suggestion")
    end

    context "with neutral mutations" do
      let(:neutral_mutation) do
        double(
          "Mutation",
          operator_name: "comparison_replacement",
          file_path: "lib/user.rb",
          line: 12,
          diff: "- x <= 5\n+ x < 5"
        )
      end

      let(:neutral_result) do
        Evilution::Result::MutationResult.new(
          mutation: neutral_mutation,
          status: :neutral,
          duration: 0.1
        )
      end

      let(:neutral_summary) do
        Evilution::Result::Summary.new(
          results: [killed_result, neutral_result],
          duration: 0.6
        )
      end

      it "includes neutral count in summary" do
        parsed = JSON.parse(reporter.call(neutral_summary))

        expect(parsed["summary"]["neutral"]).to eq(1)
      end

      it "includes neutral array with mutation details" do
        parsed = JSON.parse(reporter.call(neutral_summary))

        expect(parsed["neutral"].length).to eq(1)
        expect(parsed["neutral"].first["operator"]).to eq("comparison_replacement")
        expect(parsed["neutral"].first["status"]).to eq("neutral")
      end

      it "does not include suggestion for neutral mutations" do
        parsed = JSON.parse(reporter.call(neutral_summary))

        expect(parsed["neutral"].first).not_to have_key("suggestion")
      end

      it "excludes neutrals from score calculation" do
        parsed = JSON.parse(reporter.call(neutral_summary))

        expect(parsed["summary"]["score"]).to eq(1.0)
      end
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

    it "includes truncated when summary is truncated" do
      truncated_summary = Evilution::Result::Summary.new(results: [survived_result, killed_result], duration: 0.6, truncated: true)
      parsed = JSON.parse(reporter.call(truncated_summary))

      expect(parsed["summary"]["truncated"]).to be true
    end

    it "omits truncated when summary is not truncated" do
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["summary"]).not_to have_key("truncated")
    end

    it "includes test_command when present in mutation result" do
      result_with_command = Evilution::Result::MutationResult.new(
        mutation: survived_mutation,
        status: :survived,
        duration: 0.123,
        test_command: "rspec --format progress --no-color --order defined spec"
      )
      command_summary = Evilution::Result::Summary.new(results: [result_with_command], duration: 0.2)
      parsed = JSON.parse(reporter.call(command_summary))

      expect(parsed["survived"].first["test_command"]).to eq(
        "rspec --format progress --no-color --order defined spec"
      )
    end

    it "omits test_command when not present in mutation result" do
      parsed = JSON.parse(reporter.call(summary))

      expect(parsed["survived"].first).not_to have_key("test_command")
      expect(parsed["killed"].first).not_to have_key("test_command")
    end

    context "with skipped mutations" do
      let(:skipped_summary) do
        Evilution::Result::Summary.new(
          results: [killed_result],
          duration: 0.5,
          skipped: 4
        )
      end

      it "includes skipped count in summary" do
        parsed = JSON.parse(reporter.call(skipped_summary))

        expect(parsed["summary"]["skipped"]).to eq(4)
      end

      it "omits skipped when count is zero" do
        parsed = JSON.parse(reporter.call(summary))

        expect(parsed["summary"]).not_to have_key("skipped")
      end
    end
  end
end
