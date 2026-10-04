# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RegexpOptionRemoval do
  def mutated_patterns(regex_literal, filter: nil)
    tmpfile = Tempfile.new(["regexp_option_removal", ".rb"])
    tmpfile.write("def probe(s)\n  s.match(#{regex_literal})\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter).map { |m| m.mutated_source[/match\((.*)\)/m, 1] }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "drops the case-insensitive flag" do
      expect(mutated_patterns("/admin/i")).to eq(["/admin/"])
    end

    it "drops the multiline flag" do
      expect(mutated_patterns("/a.b/m")).to eq(["/a.b/"])
    end

    it "drops each flag separately and keeps the others" do
      expect(mutated_patterns("/a.b/xim")).to eq(["/a.b/xm", "/a.b/xi"])
      expect(mutated_patterns("%r{a.b}mi")).to eq(["%r{a.b}m", "%r{a.b}i"])
    end

    # Without a cased letter there is nothing for case-insensitivity to change.
    it "keeps the case-insensitive flag of a pattern without cased letters" do
      expect(mutated_patterns("/\\d+-\\d+/i")).to be_empty
      expect(mutated_patterns("/[0-9_]+/i")).to be_empty
    end

    it "counts a letter written next to other characters" do
      expect(mutated_patterns("/a1/i")).to eq(["/a1/"])
    end

    it "counts letters inside a character class" do
      expect(mutated_patterns("/[a-f0-9]+/i")).to eq(["/[a-f0-9]+/"])
    end

    it "counts letters outside the ASCII range" do
      expect(mutated_patterns("/é/i")).to eq(["/é/"])
    end

    it "does not count escaped letters such as \\d" do
      expect(mutated_patterns("/\\s\\w/i")).to be_empty
    end

    # The multiline flag only lets `.` match a newline.
    it "keeps the multiline flag of a pattern without a dot" do
      expect(mutated_patterns("/a\\nb/m")).to be_empty
      expect(mutated_patterns("/[.]/m")).to be_empty
      expect(mutated_patterns("/1|2/m")).to be_empty
    end

    it "leaves the other flags alone" do
      expect(mutated_patterns("/a b/x")).to be_empty
      expect(mutated_patterns("/a/o")).to be_empty
      expect(mutated_patterns("/a/n")).to be_empty
    end

    it "emits nothing for a pattern without flags" do
      expect(mutated_patterns("/a.b/")).to be_empty
    end

    it "emits nothing for a pattern regexp_parser cannot read" do
      allow(Evilution::AST::RegexpPattern).to receive(:parse).and_return(nil)

      expect(mutated_patterns("/a.b/im")).to be_empty
    end

    it "leaves interpolated patterns alone" do
      expect(mutated_patterns("/a.\#{s}/im")).to be_empty
    end

    it "produces parseable mutations" do
      tmpfile = Tempfile.new(["regexp_option_removal", ".rb"])
      tmpfile.write("def probe(s)\n  s.match(/A.b/mix)\nend\n")
      tmpfile.flush
      muts = described_class.new.call(Evilution::AST::Parser.new.call(tmpfile.path).first)

      expect(muts.length).to eq(2)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["regexp_option_removal"])
    ensure
      tmpfile.close
      tmpfile.unlink
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["regular_expression"])

      expect(mutated_patterns("/a/i", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
