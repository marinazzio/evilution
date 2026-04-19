# frozen_string_literal: true

RSpec.describe Evilution::Result::Summary do
  let(:mutation) { double("Mutation") }

  def make_result(status)
    Evilution::Result::MutationResult.new(mutation: mutation, status: status)
  end

  let(:results) do
    [
      make_result(:killed),
      make_result(:killed),
      make_result(:killed),
      make_result(:survived),
      make_result(:timeout)
    ]
  end

  subject(:summary) { described_class.new(results: results, duration: 5.2) }

  describe "#total" do
    it "returns the total number of results" do
      expect(summary.total).to eq(5)
    end
  end

  describe "#killed" do
    it "counts killed mutations" do
      expect(summary.killed).to eq(3)
    end
  end

  describe "#survived" do
    it "counts survived mutations" do
      expect(summary.survived).to eq(1)
    end
  end

  describe "#timed_out" do
    it "counts timed out mutations" do
      expect(summary.timed_out).to eq(1)
    end
  end

  describe "#errors" do
    it "counts error mutations" do
      expect(summary.errors).to eq(0)
    end
  end

  describe "#neutral" do
    it "counts neutral mutations" do
      results_with_neutral = [
        make_result(:killed),
        make_result(:neutral),
        make_result(:neutral)
      ]
      s = described_class.new(results: results_with_neutral)

      expect(s.neutral).to eq(2)
    end

    it "returns zero when no neutral mutations" do
      expect(summary.neutral).to eq(0)
    end
  end

  describe "#neutral_results" do
    it "returns only neutral results" do
      neutral_result = make_result(:neutral)
      results_with_neutral = [make_result(:killed), neutral_result]
      s = described_class.new(results: results_with_neutral)

      expect(s.neutral_results).to eq([neutral_result])
    end
  end

  describe "#equivalent" do
    it "counts equivalent mutations" do
      results_with_equivalent = [
        make_result(:killed),
        make_result(:equivalent),
        make_result(:equivalent)
      ]
      s = described_class.new(results: results_with_equivalent)

      expect(s.equivalent).to eq(2)
    end
  end

  describe "#equivalent_results" do
    it "returns only equivalent results" do
      equiv = make_result(:equivalent)
      s = described_class.new(results: [make_result(:killed), equiv])

      expect(s.equivalent_results).to eq([equiv])
    end
  end

  describe "#unparseable" do
    it "counts unparseable mutations" do
      s = described_class.new(results: [make_result(:killed), make_result(:unparseable), make_result(:unparseable)])

      expect(s.unparseable).to eq(2)
    end

    it "returns zero when no unparseable mutations" do
      expect(summary.unparseable).to eq(0)
    end
  end

  describe "#unparseable_results" do
    it "returns only unparseable results" do
      unp = make_result(:unparseable)
      s = described_class.new(results: [make_result(:killed), unp])

      expect(s.unparseable_results).to eq([unp])
    end
  end

  describe "#unresolved" do
    it "counts unresolved mutations" do
      s = described_class.new(results: [make_result(:killed), make_result(:unresolved), make_result(:unresolved)])

      expect(s.unresolved).to eq(2)
    end

    it "returns zero when no unresolved mutations" do
      expect(summary.unresolved).to eq(0)
    end
  end

  describe "#unresolved_results" do
    it "returns only unresolved results" do
      unresolved = make_result(:unresolved)
      s = described_class.new(results: [make_result(:killed), unresolved])

      expect(s.unresolved_results).to eq([unresolved])
    end
  end

  describe "#score" do
    it "calculates killed / (total - errors)" do
      expect(summary.score).to eq(3.0 / 5)
    end

    it "returns 0.0 when no mutations" do
      empty = described_class.new(results: [])

      expect(empty.score).to eq(0.0)
    end

    it "excludes errors from denominator" do
      results_with_error = [
        make_result(:killed),
        make_result(:survived),
        make_result(:error)
      ]
      s = described_class.new(results: results_with_error)

      expect(s.score).to eq(1.0 / 2)
    end

    it "excludes neutrals from denominator" do
      results_with_neutral = [
        make_result(:killed),
        make_result(:survived),
        make_result(:neutral)
      ]
      s = described_class.new(results: results_with_neutral)

      expect(s.score).to eq(1.0 / 2)
    end

    it "excludes both errors and neutrals from denominator" do
      mixed = [
        make_result(:killed),
        make_result(:survived),
        make_result(:error),
        make_result(:neutral)
      ]
      s = described_class.new(results: mixed)

      expect(s.score).to eq(1.0 / 2)
    end

    it "excludes equivalents from denominator" do
      results_with_equivalent = [
        make_result(:killed),
        make_result(:survived),
        make_result(:equivalent)
      ]
      s = described_class.new(results: results_with_equivalent)

      expect(s.score).to eq(1.0 / 2)
    end

    it "excludes unresolved from denominator" do
      results_with_unresolved = [
        make_result(:killed),
        make_result(:survived),
        make_result(:unresolved)
      ]
      s = described_class.new(results: results_with_unresolved)

      expect(s.score).to eq(1.0 / 2)
    end

    it "excludes unparseable from denominator" do
      results_with_unparseable = [
        make_result(:killed),
        make_result(:survived),
        make_result(:unparseable)
      ]
      s = described_class.new(results: results_with_unparseable)

      expect(s.score).to eq(1.0 / 2)
    end

    it "returns 0.0 when all mutations are errors (avoids NaN)" do
      all_errors = [make_result(:error), make_result(:error)]
      s = described_class.new(results: all_errors)

      expect(s.score).to eq(0.0)
    end

    it "returns 0.0 when all mutations are neutral" do
      all_neutral = [make_result(:neutral), make_result(:neutral)]
      s = described_class.new(results: all_neutral)

      expect(s.score).to eq(0.0)
    end
  end

  describe "#success?" do
    it "returns true when score meets threshold" do
      all_killed = described_class.new(results: [make_result(:killed)])

      expect(all_killed.success?).to be true
    end

    it "returns false when score below threshold" do
      expect(summary.success?).to be false
    end

    it "accepts custom min_score" do
      expect(summary.success?(min_score: 0.5)).to be true
    end
  end

  describe "#survived_results" do
    it "returns only survived results" do
      expect(summary.survived_results.length).to eq(1)
      expect(summary.survived_results.first).to be_survived
    end
  end

  describe "#killed_results" do
    it "returns only killed results" do
      expect(summary.killed_results.length).to eq(3)
    end
  end

  it "stores duration" do
    expect(summary.duration).to eq(5.2)
  end

  it "is frozen" do
    expect(summary).to be_frozen
  end

  describe "#truncated?" do
    it "defaults to false" do
      expect(summary).not_to be_truncated
    end

    it "returns true when truncated" do
      truncated_summary = described_class.new(results: results, duration: 1.0, truncated: true)

      expect(truncated_summary).to be_truncated
    end
  end

  describe "#skipped" do
    it "defaults to zero" do
      expect(summary.skipped).to eq(0)
    end

    it "returns the skipped count" do
      s = described_class.new(results: results, duration: 1.0, skipped: 5)

      expect(s.skipped).to eq(5)
    end
  end

  describe "#killtime" do
    it "sums individual mutation durations" do
      r1 = Evilution::Result::MutationResult.new(mutation: mutation, status: :killed, duration: 1.5)
      r2 = Evilution::Result::MutationResult.new(mutation: mutation, status: :survived, duration: 2.3)
      s = described_class.new(results: [r1, r2], duration: 10.0)

      expect(s.killtime).to be_within(0.001).of(3.8)
    end

    it "returns 0.0 for empty results" do
      s = described_class.new(results: [])

      expect(s.killtime).to eq(0.0)
    end
  end

  describe "#efficiency" do
    it "calculates killtime / duration as a ratio" do
      r1 = Evilution::Result::MutationResult.new(mutation: mutation, status: :killed, duration: 3.0)
      r2 = Evilution::Result::MutationResult.new(mutation: mutation, status: :survived, duration: 2.0)
      s = described_class.new(results: [r1, r2], duration: 10.0)

      expect(s.efficiency).to be_within(0.001).of(0.5)
    end

    it "returns 0.0 when duration is zero" do
      s = described_class.new(results: [make_result(:killed)], duration: 0.0)

      expect(s.efficiency).to eq(0.0)
    end
  end

  describe "#mutations_per_second" do
    it "calculates total / duration" do
      r1 = Evilution::Result::MutationResult.new(mutation: mutation, status: :killed, duration: 1.0)
      r2 = Evilution::Result::MutationResult.new(mutation: mutation, status: :survived, duration: 1.0)
      s = described_class.new(results: [r1, r2], duration: 4.0)

      expect(s.mutations_per_second).to be_within(0.001).of(0.5)
    end

    it "returns 0.0 when duration is zero" do
      s = described_class.new(results: [make_result(:killed)], duration: 0.0)

      expect(s.mutations_per_second).to eq(0.0)
    end
  end

  describe "#coverage_gaps" do
    it "groups survived results into coverage gaps" do
      subj = double("Subject", name: "User#check")
      m1 = double("Mutation", operator_name: "op1", file_path: "lib/user.rb", line: 9, diff: "- a\n+ b", subject: subj)
      m2 = double("Mutation", operator_name: "op2", file_path: "lib/user.rb", line: 9, diff: "- a\n+ c", subject: subj)
      r1 = Evilution::Result::MutationResult.new(mutation: m1, status: :survived, duration: 0.1)
      r2 = Evilution::Result::MutationResult.new(mutation: m2, status: :survived, duration: 0.1)
      s = described_class.new(results: [r1, r2, make_result(:killed)], duration: 1.0)

      gaps = s.coverage_gaps

      expect(gaps.length).to eq(1)
      expect(gaps.first.mutation_results).to contain_exactly(r1, r2)
    end

    it "returns empty array when no survivors" do
      s = described_class.new(results: [make_result(:killed)], duration: 1.0)

      expect(s.coverage_gaps).to eq([])
    end
  end

  describe "#disabled_mutations" do
    it "returns empty array by default" do
      expect(summary.disabled_mutations).to eq([])
    end

    it "returns disabled mutations when provided" do
      disabled = [double("Mutation1"), double("Mutation2")]
      s = described_class.new(results: results, duration: 1.0, disabled_mutations: disabled)

      expect(s.disabled_mutations).to eq(disabled)
    end
  end
end
