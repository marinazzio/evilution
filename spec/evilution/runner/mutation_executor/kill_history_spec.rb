# frozen_string_literal: true

require "evilution/runner/mutation_executor/kill_history"

RSpec.describe Evilution::Runner::MutationExecutor::KillHistory do
  subject(:history) { described_class.new }

  def subject_named(name)
    instance_double(Evilution::Subject, name: name)
  end

  def mutation(line, subject_name: "Gate#state", file_path: "lib/gate.rb")
    instance_double(Evilution::Mutation, file_path: file_path, line: line, subject: subject_named(subject_name))
  end

  describe "#killers_for" do
    it "has none before any kill" do
      expect(history.killers_for(mutation(5))).to eq([])
    end

    it "names the test that killed a mutation on the same line" do
      history.record(mutation(5), status: :killed, killing_test: "a[1:1]")

      expect(history.killers_for(mutation(5))).to eq(["a[1:1]"])
    end

    it "names the latest killer first" do
      history.record(mutation(5), status: :killed, killing_test: "a[1:1]")
      history.record(mutation(5), status: :killed, killing_test: "a[1:2]")

      expect(history.killers_for(mutation(5))).to eq(["a[1:2]", "a[1:1]"])
    end

    it "names a killer once, at its latest place, however often it killed" do
      history.record(mutation(5), status: :killed, killing_test: "a[1:1]")
      history.record(mutation(5), status: :killed, killing_test: "a[1:2]")
      history.record(mutation(5), status: :killed, killing_test: "a[1:1]")

      expect(history.killers_for(mutation(5))).to eq(["a[1:1]", "a[1:2]"])
    end

    it "names the killers of the same line before those of elsewhere in the subject" do
      history.record(mutation(5), status: :killed, killing_test: "a[1:1]")
      history.record(mutation(6), status: :killed, killing_test: "a[1:2]")

      expect(history.killers_for(mutation(5))).to eq(["a[1:1]", "a[1:2]"])
    end

    it "names the killers of the subject on a line nothing killed on yet" do
      history.record(mutation(5), status: :killed, killing_test: "a[1:1]")

      expect(history.killers_for(mutation(7))).to eq(["a[1:1]"])
    end

    it "keeps the killers of another subject out" do
      history.record(mutation(10, subject_name: "Gate#label"), status: :killed, killing_test: "a[1:9]")

      expect(history.killers_for(mutation(5))).to eq([])
    end

    it "keeps the killers of the same line in another file out" do
      history.record(mutation(5, file_path: "lib/other.rb", subject_name: "Other#x"), status: :killed,
                                                                                      killing_test: "a[1:9]")

      expect(history.killers_for(mutation(5))).to eq([])
    end

    it "names no more killers than its limit" do
      (described_class::LIMIT + 3).times do |i|
        history.record(mutation(5), status: :killed, killing_test: "a[1:#{i}]")
      end

      expect(history.killers_for(mutation(5)).length).to eq(described_class::LIMIT)
    end

    it "names the killers of the line first when the line and the subject hold more than its limit" do
      described_class::LIMIT.times { |i| history.record(mutation(5), status: :killed, killing_test: "a[1:#{i}]") }
      described_class::LIMIT.times { |i| history.record(mutation(6), status: :killed, killing_test: "b[1:#{i}]") }

      killers = history.killers_for(mutation(5))

      expect(killers.length).to eq(described_class::LIMIT)
      expect(killers).to all(start_with("a["))
    end

    it "keeps the latest killer when it has more than its limit" do
      (described_class::LIMIT + 1).times do |i|
        history.record(mutation(5), status: :killed, killing_test: "a[1:#{i}]")
      end

      expect(history.killers_for(mutation(5)).first).to eq("a[1:#{described_class::LIMIT}]")
      expect(history.killers_for(mutation(5))).not_to include("a[1:0]")
    end

    it "does not let one killer, however often it killed, push out the others" do
      history.record(mutation(5), status: :killed, killing_test: "b[1:1]")
      (described_class::LIMIT + 1).times { history.record(mutation(5), status: :killed, killing_test: "a[1:1]") }

      expect(history.killers_for(mutation(5))).to eq(["a[1:1]", "b[1:1]"])
    end

    it "keeps the killers of a subject of the same name in another file out" do
      history.record(mutation(9, file_path: "lib/other.rb"), status: :killed, killing_test: "a[1:9]")

      expect(history.killers_for(mutation(5))).to eq([])
    end

    it "ignores a mutation that was not killed" do
      history.record(mutation(5), status: :survived, killing_test: "a[1:1]")

      expect(history.killers_for(mutation(5))).to eq([])
    end

    it "ignores a kill without a named test" do
      history.record(mutation(5), status: :killed, killing_test: nil)

      expect(history.killers_for(mutation(5))).to eq([])
    end

    it "goes by the line alone for a mutation without a subject" do
      bare = instance_double(Evilution::Mutation, file_path: "lib/gate.rb", line: 5, subject: nil)
      history.record(bare, status: :killed, killing_test: "a[1:1]")

      expect(history.killers_for(bare)).to eq(["a[1:1]"])
    end
  end

  describe "NONE" do
    it "remembers nothing" do
      described_class::NONE.record(mutation(5), status: :killed, killing_test: "a[1:1]")

      expect(described_class::NONE.killers_for(mutation(5))).to eq([])
    end

    it "is frozen" do
      expect(described_class::NONE).to be_frozen
    end
  end
end
