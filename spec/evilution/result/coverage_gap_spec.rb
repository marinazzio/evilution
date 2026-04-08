# frozen_string_literal: true

require "evilution/result/coverage_gap"

RSpec.describe Evilution::Result::CoverageGap do
  let(:subject1) { double("Subject", name: "User#check") }

  let(:mutation1) do
    double("Mutation",
           operator_name: "comparison_replacement",
           file_path: "lib/user.rb",
           line: 9,
           diff: "- x >= 10\n+ x > 10",
           subject: subject1)
  end

  let(:mutation2) do
    double("Mutation",
           operator_name: "method_call_removal",
           file_path: "lib/user.rb",
           line: 9,
           diff: "- x >= 10\n+ nil",
           subject: subject1)
  end

  let(:result1) do
    Evilution::Result::MutationResult.new(mutation: mutation1, status: :survived, duration: 0.1)
  end

  let(:result2) do
    Evilution::Result::MutationResult.new(mutation: mutation2, status: :survived, duration: 0.2)
  end

  describe "single mutation gap" do
    subject(:gap) do
      described_class.new(
        file_path: "lib/user.rb",
        subject_name: "User#check",
        line: 9,
        mutation_results: [result1]
      )
    end

    it "returns the file path" do
      expect(gap.file_path).to eq("lib/user.rb")
    end

    it "returns the subject name" do
      expect(gap.subject_name).to eq("User#check")
    end

    it "returns the line number" do
      expect(gap.line).to eq(9)
    end

    it "returns mutation results" do
      expect(gap.mutation_results).to eq([result1])
    end

    it "returns operator names" do
      expect(gap.operator_names).to eq(["comparison_replacement"])
    end

    it "returns the primary operator" do
      expect(gap.primary_operator).to eq("comparison_replacement")
    end

    it "returns the primary diff" do
      expect(gap.primary_diff).to eq("- x >= 10\n+ x > 10")
    end

    it "returns count of 1" do
      expect(gap.count).to eq(1)
    end

    it "is single" do
      expect(gap).to be_single
    end

    it "is frozen" do
      expect(gap).to be_frozen
    end

    it "has frozen mutation_results" do
      expect(gap.mutation_results).to be_frozen
    end

    it "does not share the original array" do
      original = [result1]
      gap = described_class.new(
        file_path: "lib/user.rb",
        subject_name: "User#check",
        line: 9,
        mutation_results: original
      )
      original << result2

      expect(gap.mutation_results).to eq([result1])
    end
  end

  describe "multi-mutation gap" do
    subject(:gap) do
      described_class.new(
        file_path: "lib/user.rb",
        subject_name: "User#check",
        line: 9,
        mutation_results: [result1, result2]
      )
    end

    it "returns both operator names" do
      expect(gap.operator_names).to contain_exactly("comparison_replacement", "method_call_removal")
    end

    it "returns the first operator as primary" do
      expect(gap.primary_operator).to eq("comparison_replacement")
    end

    it "returns count of 2" do
      expect(gap.count).to eq(2)
    end

    it "is not single" do
      expect(gap).not_to be_single
    end

    it "deduplicates operator names" do
      result3 = Evilution::Result::MutationResult.new(mutation: mutation1, status: :survived, duration: 0.3)
      gap_with_dups = described_class.new(
        file_path: "lib/user.rb",
        subject_name: "User#check",
        line: 9,
        mutation_results: [result1, result3]
      )

      expect(gap_with_dups.operator_names).to eq(["comparison_replacement"])
    end
  end
end
