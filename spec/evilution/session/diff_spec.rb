# frozen_string_literal: true

RSpec.describe Evilution::Session::Diff do
  subject(:diff_engine) { described_class.new }

  def session_data(score:, total: 10, killed: 8, survived: 2, survivors: [])
    {
      "timestamp" => "2026-03-24T10:00:00+00:00",
      "summary" => {
        "total" => total,
        "killed" => killed,
        "survived" => survived,
        "timed_out" => 0,
        "errors" => 0,
        "neutral" => 0,
        "equivalent" => 0,
        "score" => score,
        "duration" => 5.0
      },
      "survived" => survivors
    }
  end

  def mutation(operator:, file:, line:, subject:, diff: "- old\n+ new")
    { "operator" => operator, "file" => file, "line" => line, "subject" => subject, "diff" => diff }
  end

  let(:mutation_a) { mutation(operator: "arithmetic_replacement", file: "lib/foo.rb", line: 10, subject: "Foo#bar") }
  let(:mutation_b) { mutation(operator: "comparison_replacement", file: "lib/foo.rb", line: 20, subject: "Foo#baz") }
  let(:mutation_c) { mutation(operator: "boolean_replacement", file: "lib/bar.rb", line: 5, subject: "Bar#check") }

  describe "#call" do
    it "returns a result with summary, fixed, new_survivors, and persistent" do
      base = session_data(score: 0.8, survivors: [mutation_a])
      head = session_data(score: 0.9, survivors: [mutation_a])

      result = diff_engine.call(base, head)

      expect(result).to respond_to(:summary, :fixed, :new_survivors, :persistent)
    end

    context "when head has improved score" do
      it "returns positive score delta" do
        base = session_data(score: 0.8, survivors: [mutation_a, mutation_b])
        head = session_data(score: 0.9, total: 10, killed: 9, survived: 1, survivors: [mutation_a])

        result = diff_engine.call(base, head)

        expect(result.summary.base_score).to eq(0.8)
        expect(result.summary.head_score).to eq(0.9)
        expect(result.summary.score_delta).to eq(0.1)
      end
    end

    context "when head has regressed score" do
      it "returns negative score delta" do
        base = session_data(score: 0.9, total: 10, killed: 9, survived: 1, survivors: [mutation_a])
        head = session_data(score: 0.7, total: 10, killed: 7, survived: 3,
                            survivors: [mutation_a, mutation_b, mutation_c])

        result = diff_engine.call(base, head)

        expect(result.summary.score_delta).to eq(-0.2)
      end
    end

    context "when scores are equal" do
      it "returns zero score delta" do
        base = session_data(score: 0.8, survivors: [mutation_a])
        head = session_data(score: 0.8, survivors: [mutation_a])

        result = diff_engine.call(base, head)

        expect(result.summary.score_delta).to eq(0.0)
      end
    end

    context "with survived count changes" do
      it "includes base and head survived counts" do
        base = session_data(score: 0.8, survived: 2, survivors: [mutation_a, mutation_b])
        head = session_data(score: 0.9, survived: 1, survivors: [mutation_a])

        result = diff_engine.call(base, head)

        expect(result.summary.base_survived).to eq(2)
        expect(result.summary.head_survived).to eq(1)
      end
    end

    context "with total and killed count changes" do
      it "includes base and head totals and killed counts" do
        base = session_data(score: 0.8, total: 10, killed: 8, survived: 2, survivors: [mutation_a, mutation_b])
        head = session_data(score: 0.9, total: 15, killed: 14, survived: 1, survivors: [mutation_a])

        result = diff_engine.call(base, head)

        expect(result.summary.base_total).to eq(10)
        expect(result.summary.head_total).to eq(15)
        expect(result.summary.base_killed).to eq(8)
        expect(result.summary.head_killed).to eq(14)
      end
    end

    context "when mutations are fixed (survived in base, not in head)" do
      it "returns them in fixed array" do
        base = session_data(score: 0.8, survivors: [mutation_a, mutation_b])
        head = session_data(score: 0.9, total: 10, killed: 9, survived: 1, survivors: [mutation_a])

        result = diff_engine.call(base, head)

        expect(result.fixed.length).to eq(1)
        expect(result.fixed.first["subject"]).to eq("Foo#baz")
      end
    end

    context "when new survivors appear (survived in head, not in base)" do
      it "returns them in new_survivors array" do
        base = session_data(score: 0.9, total: 10, killed: 9, survived: 1, survivors: [mutation_a])
        head = session_data(score: 0.7, total: 10, killed: 7, survived: 3,
                            survivors: [mutation_a, mutation_b, mutation_c])

        result = diff_engine.call(base, head)

        expect(result.new_survivors.length).to eq(2)
        subjects = result.new_survivors.map { |m| m["subject"] }
        expect(subjects).to contain_exactly("Foo#baz", "Bar#check")
      end
    end

    context "when survivors persist across both sessions" do
      it "returns them in persistent array" do
        base = session_data(score: 0.8, survivors: [mutation_a, mutation_b])
        head = session_data(score: 0.8, survivors: [mutation_a, mutation_b])

        result = diff_engine.call(base, head)

        expect(result.persistent.length).to eq(2)
      end
    end

    context "when no mutations survive in either session" do
      it "returns empty arrays" do
        base = session_data(score: 1.0, total: 10, killed: 10, survived: 0, survivors: [])
        head = session_data(score: 1.0, total: 10, killed: 10, survived: 0, survivors: [])

        result = diff_engine.call(base, head)

        expect(result.fixed).to eq([])
        expect(result.new_survivors).to eq([])
        expect(result.persistent).to eq([])
      end
    end

    context "when all survivors are replaced" do
      it "correctly categorizes all as fixed and new" do
        base = session_data(score: 0.8, survivors: [mutation_a])
        head = session_data(score: 0.8, survivors: [mutation_b])

        result = diff_engine.call(base, head)

        expect(result.fixed.length).to eq(1)
        expect(result.fixed.first["subject"]).to eq("Foo#bar")
        expect(result.new_survivors.length).to eq(1)
        expect(result.new_survivors.first["subject"]).to eq("Foo#baz")
        expect(result.persistent).to eq([])
      end
    end

    context "with missing summary keys" do
      it "defaults to zero for missing values" do
        base = { "summary" => {}, "survived" => [] }
        head = { "summary" => {}, "survived" => [] }

        result = diff_engine.call(base, head)

        expect(result.summary.base_score).to eq(0.0)
        expect(result.summary.head_score).to eq(0.0)
        expect(result.summary.score_delta).to eq(0.0)
        expect(result.summary.base_survived).to eq(0)
        expect(result.summary.head_survived).to eq(0)
        expect(result.summary.base_total).to eq(0)
        expect(result.summary.head_total).to eq(0)
      end
    end

    context "with nil survived arrays" do
      it "treats nil as empty" do
        base = { "summary" => { "score" => 0.8 }, "survived" => nil }
        head = { "summary" => { "score" => 0.9 }, "survived" => nil }

        result = diff_engine.call(base, head)

        expect(result.fixed).to eq([])
        expect(result.new_survivors).to eq([])
        expect(result.persistent).to eq([])
      end
    end

    context "mutation identity" do
      it "matches mutations by operator, file, line, and subject" do
        same_location_different_diff = mutation(
          operator: "arithmetic_replacement", file: "lib/foo.rb", line: 10,
          subject: "Foo#bar", diff: "- completely different\n+ diff text"
        )

        base = session_data(score: 0.8, survivors: [mutation_a])
        head = session_data(score: 0.8, survivors: [same_location_different_diff])

        result = diff_engine.call(base, head)

        expect(result.persistent.length).to eq(1)
        expect(result.fixed).to eq([])
        expect(result.new_survivors).to eq([])
      end

      it "treats same operator at different lines as different mutations" do
        different_line = mutation(
          operator: "arithmetic_replacement", file: "lib/foo.rb", line: 15, subject: "Foo#bar"
        )

        base = session_data(score: 0.8, survivors: [mutation_a])
        head = session_data(score: 0.8, survivors: [different_line])

        result = diff_engine.call(base, head)

        expect(result.fixed.length).to eq(1)
        expect(result.new_survivors.length).to eq(1)
        expect(result.persistent).to eq([])
      end
    end
  end

  describe "#to_h" do
    it "converts the result to a hash for JSON serialization" do
      base = session_data(score: 0.8, survivors: [mutation_a, mutation_b])
      head = session_data(score: 0.9, total: 10, killed: 9, survived: 1, survivors: [mutation_a])

      result = diff_engine.call(base, head)
      hash = result.to_h

      expect(hash).to be_a(Hash)
      expect(hash["summary"]).to include("base_score" => 0.8, "head_score" => 0.9, "score_delta" => 0.1)
      expect(hash["fixed"].length).to eq(1)
      expect(hash["new_survivors"]).to eq([])
      expect(hash["persistent"].length).to eq(1)
    end
  end
end
