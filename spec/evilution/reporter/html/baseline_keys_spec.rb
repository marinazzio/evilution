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

    # Kills EV-2bx6 / GH #1193 index_to_fetch on baseline_keys.rb:22
    # (`m["operator"|"file"|"line"|"subject"]` -> `.fetch(...)`). A partial
    # baseline entry — historical sessions or stripped JSON — must yield a
    # key tuple with `nil` placeholders rather than crashing the regression
    # detector with KeyError.
    it "tolerates baseline survivor entries missing identity fields" do
      partial_baseline = {
        "survived" => [
          { "file" => "lib/x.rb", "line" => 1, "subject" => "X#m" },
          { "operator" => "op_a", "line" => 1, "subject" => "X#m" },
          { "operator" => "op_a", "file" => "lib/x.rb", "subject" => "X#m" },
          { "operator" => "op_a", "file" => "lib/x.rb", "line" => 1 }
        ]
      }

      expect { described_class.new(partial_baseline) }.not_to raise_error
    end
  end
end
