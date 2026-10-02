# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RightwardAssignment do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["rightward_assignment", ".rb"])
    tmpfile.write("class Matcher\n  def call(value, a)\n#{body}  end\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  # The line each mutation rewrote.
  def mutated_lines(muts)
    muts.map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    it "turns a destructuring match into a predicate" do
      muts = mutations_for("    value => [first, second]\n    first + second\n")

      expect(mutated_lines(muts)).to eq(["value in [first, second]"])
    end

    it "turns a validating match into a predicate" do
      muts = mutations_for("    value => Integer\n    value\n")

      expect(mutated_lines(muts)).to eq(["value in Integer"])
    end

    it "rewrites a hash pattern without touching the hash rockets inside it" do
      muts = mutations_for("    value => { name: String => name, tags: [*] }\n    name\n")

      expect(mutated_lines(muts)).to eq(["value in { name: String => name, tags: [*] }"])
    end

    it "rewrites a match whose value is an expression" do
      muts = mutations_for("    value.fetch(:pair) => [first, ^a]\n    first\n")

      expect(mutated_lines(muts)).to eq(["value.fetch(:pair) in [first, ^a]"])
    end

    it "rewrites every match of a method" do
      muts = mutations_for("    value => [first, *]\n    first => Integer\n    first\n")

      expect(mutated_lines(muts)).to eq(["value in [first, *]", "first in Integer"])
    end

    it "rewrites a match nested in a block" do
      muts = mutations_for("    value.each do |item|\n      item => { id: Integer }\n    end\n")

      expect(mutated_lines(muts)).to eq(["item in { id: Integer }"])
    end

    # `in` is a word, so unlike `=>` it needs space around it to stay a token
    # of its own: `value=>Integer` must not become the name `valueinInteger`.
    it "separates the keyword from an adjacent value and pattern" do
      muts = mutations_for("    value=>Integer\n    value\n")

      expect(mutated_lines(muts)).to eq(["value in Integer"])
    end

    it "separates the keyword from an adjacent value only" do
      muts = mutations_for("    value=> [first, *]\n    first\n")

      expect(mutated_lines(muts)).to eq(["value in [first, *]"])
    end

    it "separates the keyword from an adjacent pattern only" do
      muts = mutations_for("    value =>[first, *]\n    first\n")

      expect(mutated_lines(muts)).to eq(["value in [first, *]"])
    end

    it "adds no space when the operator is followed by a line break" do
      muts = mutations_for("    value =>\n      Integer\n    value\n")

      expect(mutated_lines(muts)).to eq(["value in"])
    end

    it "rewrites a match nested in the value of another match" do
      muts = mutations_for("    value.each { |item| item => Integer } => [first, *]\n    first\n")

      expect(mutated_lines(muts)).to eq(
        [
          "value.each { |item| item => Integer } in [first, *]",
          "value.each { |item| item in Integer } => [first, *]"
        ]
      )
    end

    # A bare name captures any value, so the match can never raise and the
    # predicate form behaves the same.
    it "emits nothing for an irrefutable capture" do
      muts = mutations_for("    value => captured\n    captured\n")

      expect(muts).to be_empty
    end

    it "emits nothing for an irrefutable wildcard" do
      muts = mutations_for("    value => _\n    value\n")

      expect(muts).to be_empty
    end

    it "rewrites a capture that is guarded by a type" do
      muts = mutations_for("    value => Integer => number\n    number\n")

      expect(mutated_lines(muts)).to eq(["value in Integer => number"])
    end

    it "leaves a pattern predicate alone" do
      muts = mutations_for("    value in Integer\n")

      expect(muts).to be_empty
    end

    it "leaves hash arguments and rescue bindings alone" do
      muts = mutations_for("    call(:key => value)\n  rescue StandardError => e\n    e\n")

      expect(muts).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("    value => { name: String => name }\n    value => [first, ^a]\n    name\n")

      expect(muts.map(&:parse_status)).to eq(%i[ok ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    value => Integer\n    value\n")

      expect(muts.map(&:operator_name)).to eq(["rightward_assignment"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["match_required"])

      muts = mutations_for("    value => Integer\n    value\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
