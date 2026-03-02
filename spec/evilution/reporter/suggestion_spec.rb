# frozen_string_literal: true

require "evilution/reporter/suggestion"

RSpec.describe Evilution::Reporter::Suggestion do
  subject(:suggestion_reporter) { described_class.new }

  let(:subject_obj) do
    double("Subject", name: "Foo#bar", file_path: "lib/foo.rb")
  end

  def build_mutation(operator_name)
    double(
      "Mutation",
      operator_name: operator_name,
      file_path: "lib/foo.rb",
      line: 5,
      diff: "- a >= b\n+ a > b"
    )
  end

  def build_result(mutation, status: :survived)
    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: status,
      duration: 0.1
    )
  end

  describe "#call" do
    it "returns suggestions for survived mutations" do
      mutation = build_mutation("comparison_replacement")
      survived = build_result(mutation)
      summary = Evilution::Result::Summary.new(results: [survived])

      result = suggestion_reporter.call(summary)

      expect(result.size).to eq(1)
      expect(result.first[:mutation]).to eq(mutation)
      expect(result.first[:suggestion]).to include("boundary condition")
    end

    it "skips killed mutations" do
      mutation = build_mutation("comparison_replacement")
      killed = build_result(mutation, status: :killed)
      summary = Evilution::Result::Summary.new(results: [killed])

      result = suggestion_reporter.call(summary)

      expect(result).to be_empty
    end

    it "generates suggestions for all 18 operator types" do
      Evilution::Reporter::Suggestion::TEMPLATES.each_key do |operator_name|
        mutation = build_mutation(operator_name)
        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to be_a(String)
        expect(suggestion.length).to be > 10
      end
    end

    it "returns a default suggestion for unknown operators" do
      mutation = build_mutation("unknown_operator")

      suggestion = suggestion_reporter.suggestion_for(mutation)

      expect(suggestion).to eq(Evilution::Reporter::Suggestion::DEFAULT_SUGGESTION)
    end

    it "handles multiple survived mutations" do
      m1 = build_mutation("comparison_replacement")
      m2 = build_mutation("boolean_operator_replacement")
      results = [build_result(m1), build_result(m2)]
      summary = Evilution::Result::Summary.new(results: results)

      suggestions = suggestion_reporter.call(summary)

      expect(suggestions.size).to eq(2)
      expect(suggestions.map { |s| s[:suggestion] }.uniq.size).to eq(2)
    end

    it "handles an empty summary" do
      summary = Evilution::Result::Summary.new(results: [])

      result = suggestion_reporter.call(summary)

      expect(result).to eq([])
    end
  end
end
