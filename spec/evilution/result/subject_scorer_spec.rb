# frozen_string_literal: true

RSpec.describe Evilution::Result::SubjectScorer do
  subject(:scorer) { described_class.new }

  def result(status, subject_name, file: "lib/helper.rb")
    subject_obj = instance_double(Evilution::Subject, name: subject_name)
    mutation = instance_double(Evilution::Mutation, subject: subject_obj, file_path: file)
    Evilution::Result::MutationResult.new(mutation: mutation, status: status, duration: 0.01)
  end

  describe "#call" do
    it "returns nothing for no results" do
      expect(scorer.call([])).to be_empty
    end

    it "scores a subject whose mutations were all killed" do
      scores = scorer.call([result(:killed, "Helper#label_for"), result(:killed, "Helper#label_for")])

      expect(scores.map { |s| [s.name, s.killed, s.verified, s.score] })
        .to eq([["Helper#label_for", 2, 2, 1.0]])
    end

    it "scores a subject with survivors" do
      results = [result(:killed, "Helper#label_for")] + Array.new(3) { result(:survived, "Helper#label_for") }

      expect(scorer.call(results).map(&:score)).to eq([0.25])
    end

    it "keeps subjects apart" do
      results = [result(:killed, "Helper#a"), result(:survived, "Helper#b")]

      expect(scorer.call(results).map(&:name)).to eq(["Helper#a", "Helper#b"])
    end

    it "keeps same-named subjects in different files apart" do
      results = [result(:killed, "Helper#call", file: "lib/a.rb"), result(:killed, "Helper#call", file: "lib/b.rb")]

      expect(scorer.call(results).map(&:file_path)).to eq(["lib/a.rb", "lib/b.rb"])
    end

    # The statuses that carry no verdict are out of the denominator, exactly as
    # they are for the run's own score.
    it "leaves unresolved, neutral, equivalent, errored and unparseable out of the denominator" do
      results = [
        result(:killed, "Helper#call"), result(:unresolved, "Helper#call"),
        result(:neutral, "Helper#call"), result(:equivalent, "Helper#call"),
        result(:error, "Helper#call"), result(:unparseable, "Helper#call")
      ]

      score = scorer.call(results).first

      expect([score.total, score.verified, score.killed, score.score]).to eq([6, 1, 1, 1.0])
    end

    # This is the shape the report is for: mutations were generated, none of
    # them got a verdict, and the file's own score says nothing about it.
    it "reports a subject nothing reached" do
      results = Array.new(18) { result(:unresolved, "Helper#summary_for") }

      score = scorer.call(results).first

      expect([score.reached?, score.score, score.total, score.verified]).to eq([false, 0.0, 18, 0])
    end

    # A timeout is a verdict — the mutation was reached and the tests did not
    # come back — but it is not a detection, so it counts towards the
    # denominator without counting as a kill.
    it "counts a timeout towards the denominator but not as a kill" do
      score = scorer.call([result(:timeout, "Helper#call")]).first

      expect([score.reached?, score.verified, score.killed, score.score]).to eq([true, 1, 0, 0.0])
    end

    it "scores a subject whose mutations were killed and timed out" do
      results = [result(:killed, "Helper#call"), result(:timeout, "Helper#call")]

      expect(scorer.call(results).first.score).to eq(0.5)
    end

    it "sorts by file and then by subject name" do
      results = [
        result(:killed, "Helper#z", file: "lib/b.rb"),
        result(:killed, "Helper#a", file: "lib/b.rb"),
        result(:killed, "Helper#m", file: "lib/a.rb")
      ]

      expect(scorer.call(results).map { |s| [s.file_path, s.name] })
        .to eq([["lib/a.rb", "Helper#m"], ["lib/b.rb", "Helper#a"], ["lib/b.rb", "Helper#z"]])
    end
  end

  describe "a score" do
    it "is fully verified when every mutation it reached was killed" do
      expect(scorer.call([result(:killed, "Helper#call")]).first).to be_fully_verified
    end

    it "is not fully verified when a mutation survived" do
      expect(scorer.call([result(:survived, "Helper#call")]).first).not_to be_fully_verified
    end

    it "is not fully verified when nothing reached it" do
      expect(scorer.call([result(:unresolved, "Helper#call")]).first).not_to be_fully_verified
    end
  end
end
