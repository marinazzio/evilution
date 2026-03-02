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

    it "returns 0.0 when all mutations are errors (avoids NaN)" do
      all_errors = [make_result(:error), make_result(:error)]
      s = described_class.new(results: all_errors)

      expect(s.score).to eq(0.0)
      expect(s.score).not_to be_nan
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
end
