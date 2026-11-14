# frozen_string_literal: true

require "evilution/mutation"
require "evilution/subject"
require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor/probe_first"

RSpec.describe Evilution::Runner::MutationExecutor::ProbeFirst do
  subject(:probe) { described_class.new }

  def subject_named(name, line: 3)
    instance_double(Evilution::Subject, name: name, line_number: line)
  end

  def mutation(operator: "integer_literal", line: 4, subject: subject_named("Gate#state"), file_path: "lib/gate.rb")
    instance_double(Evilution::Mutation, operator_name: operator, line: line, subject: subject, file_path: file_path)
  end

  def sentinel(subject: subject_named("Gate#state"), file_path: "lib/gate.rb")
    mutation(operator: "method_body_to_raise", line: 3, subject: subject, file_path: file_path)
  end

  def result(mut, status)
    Evilution::Result::MutationResult.new(mutation: mut, status: status)
  end

  describe "#sentinel?" do
    it "is true for the whole-body raise of the subject's own method" do
      expect(probe.sentinel?(sentinel)).to be true
    end

    it "compares the operator name by value, as a built name is not the same object" do
      expect(probe.sentinel?(mutation(operator: +"method_body_to_raise", line: 3))).to be true
    end

    it "is false for another operator on the def line" do
      expect(probe.sentinel?(mutation(operator: "method_body_replacement", line: 3))).to be false
    end

    it "is false for a body raise of a method nested in the subject, which starts on another line" do
      expect(probe.sentinel?(mutation(operator: "method_body_to_raise", line: 5))).to be false
    end

    it "is false for a mutation without a subject" do
      expect(probe.sentinel?(mutation(operator: "method_body_to_raise", line: 3, subject: nil))).to be false
    end
  end

  describe "#implied_by" do
    it "names the sentinel's operator for a sibling once the sentinel survived" do
      probe.record(result(sentinel, :survived))

      expect(probe.implied_by(mutation)).to eq("method_body_to_raise")
    end

    it "treats a sentinel no test executes like a survivor" do
      probe.record(result(sentinel, :uncovered))

      expect(probe.implied_by(mutation)).to eq("method_body_to_raise")
    end

    %i[killed timeout error neutral unresolved].each do |status|
      it "implies nothing when the sentinel came out #{status}" do
        probe.record(result(sentinel, status))

        expect(probe.implied_by(mutation)).to be_nil
      end
    end

    it "implies nothing before the sentinel has a verdict" do
      expect(probe.implied_by(mutation)).to be_nil
    end

    it "implies nothing for the sentinel itself" do
      probe.record(result(sentinel, :survived))

      expect(probe.implied_by(sentinel)).to be_nil
    end

    it "implies nothing for another subject" do
      probe.record(result(sentinel, :survived))

      expect(probe.implied_by(mutation(subject: subject_named("Gate#label")))).to be_nil
    end

    it "implies nothing for a subject of the same name in another file" do
      probe.record(result(sentinel, :survived))

      expect(probe.implied_by(mutation(file_path: "lib/other.rb"))).to be_nil
    end

    it "implies nothing for a method of the same name defined again on another line" do
      probe.record(result(sentinel, :survived))
      redefined = subject_named("Gate#state", line: 30)

      expect(probe.implied_by(mutation(line: 31, subject: redefined))).to be_nil
    end

    it "implies nothing for a mutation without a subject" do
      probe.record(result(sentinel, :survived))

      expect(probe.implied_by(mutation(subject: nil))).to be_nil
    end

    it "learns nothing from a survivor that is not a sentinel" do
      probe.record(result(mutation(line: 5), :survived))

      expect(probe.implied_by(mutation)).to be_nil
    end
  end

  describe "#split" do
    it "puts the sentinels first and keeps the order within each part" do
      first = mutation(line: 4)
      second = sentinel
      third = mutation(line: 6)
      fourth = sentinel(subject: subject_named("Gate#label"))

      expect(probe.split([first, second, third, fourth])).to eq([[second, fourth], [first, third]])
    end
  end

  describe "NONE" do
    it "implies nothing and knows no sentinel" do
      none = described_class::NONE
      none.record(result(sentinel, :survived))

      expect([none.implied_by(mutation), none.sentinel?(sentinel)]).to eq([nil, false])
    end
  end
end
