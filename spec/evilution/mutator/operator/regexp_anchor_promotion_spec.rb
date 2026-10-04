# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RegexpAnchorPromotion do
  def mutated_patterns(regex_literal, filter: nil)
    tmpfile = Tempfile.new(["regexp_anchor_promotion", ".rb"])
    tmpfile.write("def probe(s)\n  s.match?(#{regex_literal})\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter).map { |m| m.mutated_source[/match\?\((.*)\)/m, 1] }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "promotes a start-of-line anchor to start of string" do
      expect(mutated_patterns("/^admin/")).to eq(["/\\Aadmin/"])
    end

    it "promotes an end-of-line anchor to end of string" do
      expect(mutated_patterns("/admin$/")).to eq(["/admin\\z/"])
    end

    # \Z still lets a trailing newline through; \z does not.
    it "tightens an end-of-string anchor that allows a trailing newline" do
      expect(mutated_patterns("/admin\\Z/")).to eq(["/admin\\z/"])
    end

    it "promotes each anchor separately" do
      expect(mutated_patterns("/^[a-z]+$/")).to eq(["/\\A[a-z]+$/", "/^[a-z]+\\z/"])
    end

    it "promotes anchors inside groups and alternations" do
      expect(mutated_patterns("/(?:^a|b$)/")).to eq(["/(?:\\Aa|b$)/", "/(?:^a|b\\z)/"])
    end

    it "leaves string anchors and other assertions alone" do
      expect(mutated_patterns("/\\Aa\\z/")).to be_empty
      expect(mutated_patterns("/\\ba\\B\\G/")).to be_empty
    end

    it "leaves ^ and $ inside a character class alone" do
      expect(mutated_patterns("/[$^]/")).to be_empty
      expect(mutated_patterns("/[^a]/")).to be_empty
    end

    it "leaves escaped ^ and $ alone" do
      expect(mutated_patterns("/\\^a\\$/")).to be_empty
    end

    it "leaves the comments of an extended pattern alone" do
      expect(mutated_patterns("/a # ^ $\n/x")).to be_empty
    end

    it "keeps the literal's delimiters, flags and multibyte text" do
      expect(mutated_patterns("%r{^é/…}i")).to eq(["%r{\\Aé/…}i"])
    end

    it "emits nothing for a pattern regexp_parser cannot read" do
      allow(Evilution::AST::RegexpPattern).to receive(:parse).and_return(nil)

      expect(mutated_patterns("/^a$/")).to be_empty
    end

    it "leaves interpolated patterns alone" do
      expect(mutated_patterns("/^\#{s}$/")).to be_empty
    end

    it "produces parseable mutations" do
      tmpfile = Tempfile.new(["regexp_anchor_promotion", ".rb"])
      tmpfile.write("def probe(s)\n  s.match?(/^a$|b\\Z/)\nend\n")
      tmpfile.flush
      muts = described_class.new.call(Evilution::AST::Parser.new.call(tmpfile.path).first)

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["regexp_anchor_promotion"])
    ensure
      tmpfile.close
      tmpfile.unlink
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["regular_expression"])

      expect(mutated_patterns("/^a/", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
