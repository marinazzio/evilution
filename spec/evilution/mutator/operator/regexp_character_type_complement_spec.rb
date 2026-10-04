# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RegexpCharacterTypeComplement do
  def mutated_patterns(regex_literal, filter: nil)
    tmpfile = Tempfile.new(["regexp_character_type_complement", ".rb"])
    tmpfile.write("def probe(s)\n  s.match?(#{regex_literal})\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter).map { |m| m.mutated_source[/match\?\((.*)\)/m, 1] }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "flips each character type to its complement and back" do
      {
        "\\d" => "\\D", "\\D" => "\\d", "\\s" => "\\S", "\\S" => "\\s",
        "\\w" => "\\W", "\\W" => "\\w", "\\h" => "\\H", "\\H" => "\\h"
      }.each do |type, complement|
        expect(mutated_patterns("/a#{type}b/")).to eq(["/a#{complement}b/"])
      end
    end

    it "flips a word boundary to its complement and back" do
      expect(mutated_patterns("/\\bword\\B/")).to eq(["/\\Bword\\B/", "/\\bword\\b/"])
    end

    it "flips each character type of a pattern separately" do
      expect(mutated_patterns("/\\d+-\\w+/")).to eq(["/\\D+-\\w+/", "/\\d+-\\W+/"])
    end

    it "flips a character type inside a character class" do
      expect(mutated_patterns("/[\\d_]/")).to eq(["/[\\D_]/"])
    end

    # Inside a class `\b` is a backspace, not a word boundary, and `[\B]` is
    # a literal B.
    it "leaves a backspace escape inside a character class alone" do
      expect(mutated_patterns("/[\\b]/")).to be_empty
      expect(mutated_patterns("/[\\b\\d]/")).to eq(["/[\\b\\D]/"])
    end

    # \X (grapheme cluster) and \R (line break) overlap: \X matches "\n" too,
    # so swapping them is not an inversion.
    it "leaves grapheme and line-break escapes alone" do
      expect(mutated_patterns("/\\X\\R/")).to be_empty
    end

    it "leaves escaped backslashes and literal letters alone" do
      expect(mutated_patterns("/a\\\\d/")).to be_empty
      expect(mutated_patterns("/dswh/")).to be_empty
    end

    it "leaves properties alone" do
      expect(mutated_patterns("/\\p{Digit}/")).to be_empty
    end

    it "keeps the literal's delimiters and flags" do
      expect(mutated_patterns("%r{\\d/x}i")).to eq(["%r{\\D/x}i"])
    end

    it "keeps multibyte text around the edit" do
      expect(mutated_patterns("/é\\d…/")).to eq(["/é\\D…/"])
    end

    it "leaves the comments of an extended pattern alone" do
      expect(mutated_patterns("/\\d # \\w here\n/x")).to eq(["/\\D # \\w here\n/x"])
    end

    it "emits nothing for a pattern regexp_parser cannot read" do
      allow(Evilution::AST::RegexpPattern).to receive(:parse).and_return(nil)

      expect(mutated_patterns("/\\d/")).to be_empty
    end

    it "leaves interpolated patterns alone" do
      expect(mutated_patterns("/\#{s}\\d/")).to be_empty
    end

    it "produces parseable mutations" do
      tmpfile = Tempfile.new(["regexp_character_type_complement", ".rb"])
      tmpfile.write("def probe(s)\n  s.match?(/\\b\\d+\\s\\w/)\nend\n")
      tmpfile.flush
      muts = described_class.new.call(Evilution::AST::Parser.new.call(tmpfile.path).first)

      expect(muts.length).to eq(4)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["regexp_character_type_complement"])
    ensure
      tmpfile.close
      tmpfile.unlink
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["regular_expression"])

      expect(mutated_patterns("/\\d/", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
