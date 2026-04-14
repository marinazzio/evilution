# frozen_string_literal: true

require "evilution/reporter/html/baseline_keys"

RSpec.describe Evilution::Reporter::HTML::BaselineKeys do
  def mutation(op:, file:, line:, subject_name:)
    subj = double("Subject", name: subject_name)
    double("Mutation", operator_name: op, file_path: file, line: line, subject: subj)
  end

  describe "#regression?" do
    let(:baseline) do
      {
        "survived" => [
          { "operator" => "op_a", "file" => "lib/x.rb", "line" => 1, "subject" => "X#m" }
        ]
      }
    end

    it "returns false when no baseline given" do
      keys = described_class.new(nil)
      expect(keys.regression?(mutation(op: "op_a", file: "lib/x.rb", line: 1, subject_name: "X#m"))).to be false
    end

    it "returns false when mutation matches a baseline survivor" do
      keys = described_class.new(baseline)
      expect(keys.regression?(mutation(op: "op_a", file: "lib/x.rb", line: 1, subject_name: "X#m"))).to be false
    end

    it "returns true when mutation is not in baseline" do
      keys = described_class.new(baseline)
      expect(keys.regression?(mutation(op: "op_b", file: "lib/x.rb", line: 1, subject_name: "X#m"))).to be true
    end

    it "treats missing survived key as empty list" do
      keys = described_class.new({})
      expect(keys.regression?(mutation(op: "op_a", file: "lib/x.rb", line: 1, subject_name: "X#m"))).to be true
    end
  end
end
