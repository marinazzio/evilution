# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RegexpQuantifierMinimumSwap do
  def mutated_patterns(regex_literal, filter: nil)
    tmpfile = Tempfile.new(["regexp_quantifier_minimum_swap", ".rb"])
    tmpfile.write("def probe(s)\n  s.match?(#{regex_literal})\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter).map { |m| m.mutated_source[/match\?\((.*)\)/m, 1] }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "requires at least one occurrence where none was required" do
      expect(mutated_patterns("/\\A\\d*\\z/")).to eq(["/\\A\\d+\\z/"])
    end

    it "allows no occurrence where one was required" do
      expect(mutated_patterns("/\\A\\d+\\z/")).to eq(["/\\A\\d*\\z/"])
    end

    it "keeps a quantifier lazy or possessive" do
      expect(mutated_patterns("/a*?/")).to eq(["/a+?/"])
      expect(mutated_patterns("/a+?/")).to eq(["/a*?/"])
      expect(mutated_patterns("/a*+/")).to eq(["/a++/"])
      expect(mutated_patterns("/a++/")).to eq(["/a*+/"])
    end

    it "swaps each quantifier of a pattern separately" do
      expect(mutated_patterns("/(ab)*c+/")).to eq(["/(ab)+c+/", "/(ab)*c*/"])
    end

    it "leaves optional and interval quantifiers alone" do
      expect(mutated_patterns("/a?b{0,}c{1,3}/")).to be_empty
    end

    it "leaves * and + that are not quantifiers alone" do
      expect(mutated_patterns("/[*+]\\*\\+/")).to be_empty
      expect(mutated_patterns("/a # b*\n/x")).to be_empty
    end

    # Making a recursive call mandatory makes the pattern recurse forever.
    it "skips a swap that leaves a pattern which no longer compiles" do
      expect(mutated_patterns("/\\A(?<p>a\\g<p>*b)\\z/")).to be_empty
    end

    it "keeps the literal's delimiters, flags and multibyte text" do
      expect(mutated_patterns("%r{é*/…}i")).to eq(["%r{é+/…}i"])
    end

    it "emits nothing for a pattern regexp_parser cannot read" do
      allow(Evilution::AST::RegexpPattern).to receive(:parse).and_return(nil)

      expect(mutated_patterns("/a*/")).to be_empty
    end

    it "leaves interpolated patterns alone" do
      expect(mutated_patterns("/\#{s}*/")).to be_empty
    end

    it "produces parseable mutations" do
      tmpfile = Tempfile.new(["regexp_quantifier_minimum_swap", ".rb"])
      tmpfile.write("def probe(s)\n  s.match?(/a*b+?c*+/)\nend\n")
      tmpfile.flush
      muts = described_class.new.call(Evilution::AST::Parser.new.call(tmpfile.path).first)

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["regexp_quantifier_minimum_swap"])
    ensure
      tmpfile.close
      tmpfile.unlink
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["regular_expression"])

      expect(mutated_patterns("/a*/", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
