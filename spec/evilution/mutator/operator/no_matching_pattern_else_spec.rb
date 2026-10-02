# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::NoMatchingPatternElse do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["no_matching_pattern_else", ".rb"])
    tmpfile.write("class Matcher\n  def call(value)\n#{body}  end\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  # The method body of each mutant.
  def mutated_bodies(muts)
    muts.map { |m| m.mutated_source[/  def call\(value\)\n(.*)  end\nend\n\z/m, 1] }
  end

  describe "#call" do
    it "adds an empty else to a case/in that has none" do
      muts = mutations_for("    case value\n    in Integer then :int\n    in String then :str\n    end\n")

      expect(mutated_bodies(muts)).to eq(
        ["    case value\n    in Integer then :int\n    in String then :str\n    else\n    end\n"]
      )
    end

    it "indents the else like the end it is placed before" do
      muts = mutations_for("    result =\n      case value\n      in Integer\n        :int\n      end\n    result\n")

      expect(mutated_bodies(muts)).to eq(
        ["    result =\n      case value\n      in Integer\n        :int\n      else\n      end\n    result\n"]
      )
    end

    it "adds the else on the same line when the end is not on its own" do
      muts = mutations_for("    case value; in Integer then :int; end\n")

      expect(mutated_bodies(muts)).to eq(["    case value; in Integer then :int; else; end\n"])
    end

    it "keeps what follows the end" do
      muts = mutations_for("    case value\n    in Integer then :int\n    end.to_s\n")

      expect(mutated_bodies(muts)).to eq(["    case value\n    in Integer then :int\n    else\n    end.to_s\n"])
    end

    it "adds an else to each of two nested matches" do
      source = "    case value\n    in [inner]\n      case inner\n      in Integer then :int\n      end\n    end\n"

      expect(mutated_bodies(mutations_for(source))).to eq(
        [
          "    case value\n    in [inner]\n      case inner\n      in Integer then :int\n      end\n    else\n    end\n",
          "    case value\n    in [inner]\n      case inner\n      in Integer then :int\n      else\n      end\n    end\n"
        ]
      )
    end

    # Removing an else that is there belongs to CaseIn.
    it "emits nothing for a case/in that has an else" do
      expect(mutations_for("    case value\n    in Integer then :int\n    else :other\n    end\n")).to be_empty
      expect(mutations_for("    case value\n    in Integer then :int\n    else\n    end\n")).to be_empty
    end

    # A bare name matches every value, so an else after it could never run.
    it "emits nothing when a clause captures every value" do
      expect(mutations_for("    case value\n    in Integer then :int\n    in other then other\n    end\n")).to be_empty
      expect(mutations_for("    case value\n    in _ then :any\n    end\n")).to be_empty
    end

    it "adds an else when the capturing clause is guarded" do
      muts = mutations_for("    case value\n    in other if other.positive? then other\n    end\n")

      expect(mutated_bodies(muts)).to eq(
        ["    case value\n    in other if other.positive? then other\n    else\n    end\n"]
      )
    end

    it "adds an else when the capture is constrained by a type" do
      muts = mutations_for("    case value\n    in Integer => number then number\n    end\n")

      expect(muts.length).to eq(1)
    end

    it "emits nothing for a case/when" do
      expect(mutations_for("    case value\n    when Integer then :int\n    end\n")).to be_empty
    end

    it "emits nothing for a one-line pattern match" do
      expect(mutations_for("    value => Integer\n    value in String\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("    case value\n    in Integer then :int\n    end\n    case value; in String then :str; end\n")

      expect(muts.map(&:parse_status)).to eq(%i[ok ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    case value\n    in Integer then :int\n    end\n")

      expect(muts.map(&:operator_name)).to eq(["no_matching_pattern_else"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["case_match"])

      muts = mutations_for("    case value\n    in Integer then :int\n    end\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
