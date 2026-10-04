# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RegexpAlternationBranchDeletion do
  def mutated_patterns(regex_literal, filter: nil)
    tmpfile = Tempfile.new(["regexp_alternation_branch_deletion", ".rb"])
    tmpfile.write("def probe(s)\n  s.match?(#{regex_literal})\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter).map { |m| m.mutated_source[/match\?\((.*)\)/m, 1] }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "deletes each branch of an alternation in turn" do
      expect(mutated_patterns("/cat|dog/")).to eq(["/dog/", "/cat/"])
      expect(mutated_patterns("/a|b|c/")).to eq(["/b|c/", "/a|c/", "/a|b/"])
    end

    it "deletes a branch inside a group" do
      expect(mutated_patterns("/(?:get|post)s?/")).to eq(["/(?:post)s?/", "/(?:get)s?/"])
    end

    it "deletes the branches of nested alternations separately" do
      expect(mutated_patterns("/a|(b|c)/")).to eq(["/(b|c)/", "/a/", "/a|(c)/", "/a|(b)/"])
    end

    it "deletes an empty branch and the branch next to it" do
      expect(mutated_patterns("/(a|)/")).to eq(["/()/", "/(a)/"])
    end

    # A long alternation is a lookup table rather than logic: one deletion per
    # entry floods the report with survivors nobody acts on.
    it "skips an alternation of more than ten branches" do
      ten = (1..10).map { |i| "w#{i}" }.join("|")
      eleven = (1..11).map { |i| "w#{i}" }.join("|")

      expect(mutated_patterns("/#{ten}/").length).to eq(10)
      expect(mutated_patterns("/#{eleven}/")).to be_empty
    end

    it "still deletes the branches of a short alternation next to a long one" do
      eleven = (1..11).map { |i| "w#{i}" }.join("|")

      expect(mutated_patterns("/(?:#{eleven})(?:x|y)/").length).to eq(2)
    end

    # Deleting a branch that defines a group breaks a call to it elsewhere in
    # the pattern; that mutant would not load.
    it "skips a deletion that leaves a pattern which no longer compiles" do
      expect(mutated_patterns("/(?<x>a)|\\g<x>b/")).to eq(["/(?<x>a)/"])
      expect(mutated_patterns("/(a)|\\1b/")).to eq(["/(a)/"])
    end

    it "leaves a literal pipe alone" do
      expect(mutated_patterns("/[a|b]/")).to be_empty
      expect(mutated_patterns("/a\\|b/")).to be_empty
    end

    it "keeps the comments of an extended pattern with their branch" do
      expect(mutated_patterns("/a # x|y\n|b/x")).to eq(["/b/x", "/a # x|y\n/x"])
    end

    it "keeps the literal's delimiters, flags and multibyte text" do
      expect(mutated_patterns("%r{é|…/}i")).to eq(["%r{…/}i", "%r{é}i"])
    end

    it "emits nothing for a pattern regexp_parser cannot read" do
      allow(Evilution::AST::RegexpPattern).to receive(:parse).and_return(nil)

      expect(mutated_patterns("/a|b/")).to be_empty
    end

    it "leaves interpolated patterns alone" do
      expect(mutated_patterns("/a|\#{s}/")).to be_empty
    end

    it "produces parseable mutations" do
      tmpfile = Tempfile.new(["regexp_alternation_branch_deletion", ".rb"])
      tmpfile.write("def probe(s)\n  s.match?(/a|(b|c)|/)\nend\n")
      tmpfile.flush
      muts = described_class.new.call(Evilution::AST::Parser.new.call(tmpfile.path).first)

      expect(muts.length).to eq(5)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["regexp_alternation_branch_deletion"])
    ensure
      tmpfile.close
      tmpfile.unlink
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["regular_expression"])

      expect(mutated_patterns("/a|b/", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(2)
    end
  end
end
