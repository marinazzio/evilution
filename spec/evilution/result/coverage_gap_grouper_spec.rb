# frozen_string_literal: true

require "evilution/result/coverage_gap_grouper"

RSpec.describe Evilution::Result::CoverageGapGrouper do
  subject(:grouper) { described_class.new }

  let(:subject1) { double("Subject", name: "User#check") }
  let(:subject2) { double("Subject", name: "User#admin?") }

  def make_survived(operator_name:, file_path:, line:, subj:, diff: "- old\n+ new")
    mutation = double("Mutation",
                      operator_name: operator_name,
                      file_path: file_path,
                      line: line,
                      diff: diff,
                      subject: subj)
    Evilution::Result::MutationResult.new(mutation: mutation, status: :survived, duration: 0.1)
  end

  it "groups mutations on the same file, subject, and line" do
    r1 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 9, subj: subject1)
    r2 = make_survived(operator_name: "method_call_removal", file_path: "lib/user.rb", line: 9, subj: subject1)

    gaps = grouper.call([r1, r2])

    expect(gaps.length).to eq(1)
    expect(gaps.first.mutation_results).to contain_exactly(r1, r2)
    expect(gaps.first.file_path).to eq("lib/user.rb")
    expect(gaps.first.subject_name).to eq("User#check")
    expect(gaps.first.line).to eq(9)
  end

  it "keeps mutations on different lines separate" do
    r1 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 9, subj: subject1)
    r2 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 15, subj: subject1)

    gaps = grouper.call([r1, r2])

    expect(gaps.length).to eq(2)
  end

  it "keeps mutations in different subjects separate even on the same line" do
    r1 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 9, subj: subject1)
    r2 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 9, subj: subject2)

    gaps = grouper.call([r1, r2])

    expect(gaps.length).to eq(2)
  end

  it "keeps mutations in different files separate" do
    r1 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 9, subj: subject1)
    r2 = make_survived(operator_name: "comparison_replacement", file_path: "lib/account.rb", line: 9, subj: subject1)

    gaps = grouper.call([r1, r2])

    expect(gaps.length).to eq(2)
  end

  it "produces single gaps for lone mutations" do
    r1 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 9, subj: subject1)

    gaps = grouper.call([r1])

    expect(gaps.length).to eq(1)
    expect(gaps.first).to be_single
  end

  it "sorts gaps by file path, line, then subject name" do
    r1 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 20, subj: subject1)
    r2 = make_survived(operator_name: "comparison_replacement", file_path: "lib/account.rb", line: 5, subj: subject1)
    r3 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 10, subj: subject1)

    gaps = grouper.call([r1, r2, r3])

    expect(gaps.map(&:file_path)).to eq(["lib/account.rb", "lib/user.rb", "lib/user.rb"])
    expect(gaps.map(&:line)).to eq([5, 10, 20])
  end

  it "sorts deterministically when file and line match but subjects differ" do
    r1 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 9, subj: subject2)
    r2 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 9, subj: subject1)

    gaps = grouper.call([r1, r2])

    expect(gaps.map(&:subject_name)).to eq(["User#admin?", "User#check"])
  end

  it "returns empty array for empty input" do
    expect(grouper.call([])).to eq([])
  end

  it "returns CoverageGap instances" do
    r1 = make_survived(operator_name: "comparison_replacement", file_path: "lib/user.rb", line: 9, subj: subject1)

    gaps = grouper.call([r1])

    expect(gaps.first).to be_a(Evilution::Result::CoverageGap)
  end
end
