# frozen_string_literal: true

RSpec.describe Evilution::Reporter::JSON::Subjects do
  subject(:builder) { described_class.new }

  def score(name: "Helper#call", file: "lib/helper.rb", total: 4, killed: 3, verified: 4, survived: 1)
    Evilution::Result::SubjectScore.new(
      name: name, file_path: file, total: total, killed: killed, verified: verified, survived: survived
    )
  end

  def summary_with(*scores)
    instance_double(Evilution::Result::Summary, subject_scores: scores)
  end

  describe "#call" do
    it "returns nothing when there are no subjects" do
      expect(builder.call(summary_with)).to eq([])
    end

    it "describes a subject in full" do
      expect(builder.call(summary_with(score))).to eq(
        [{ name: "Helper#call", file: "lib/helper.rb", total: 4, killed: 3,
           verified: 4, survived: 1, score: 0.75, reached: true }]
      )
    end

    # Consumers filter on these two, so an unreached subject has to be
    # distinguishable from one whose mutations all survived.
    it "marks a subject nothing reached" do
      row = builder.call(summary_with(score(total: 9, killed: 0, verified: 0, survived: 0))).first

      expect([row[:reached], row[:score], row[:total]]).to eq([false, 0.0, 9])
    end

    it "rounds the score to four decimals" do
      row = builder.call(summary_with(score(total: 3, killed: 1, verified: 3, survived: 2))).first

      expect(row[:score]).to eq(0.3333)
    end

    it "keeps every subject, including the fully-verified ones" do
      rows = builder.call(summary_with(score(name: "Helper#a"), score(name: "Helper#b", killed: 4, survived: 0)))

      expect(rows.map { |r| r[:name] }).to eq(["Helper#a", "Helper#b"])
    end
  end
end
