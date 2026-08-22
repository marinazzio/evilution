# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IfBranchSwap do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/if_branch_swap.rb", __dir__) }
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name)
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subject)
  end

  # Isolate the mutated method so an expectation reads as the resulting
  # source rather than a byte offset.
  def mutated_bodies(muts, method_name)
    muts.map { |m| m.mutated_source[/  def #{method_name}\b.*?\n  end\n/m] }
  end

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["if_branch_swap", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "replaces the if-branch with the else body and drops the else" do
      muts = mutations_for("pick")

      expect(mutated_bodies(muts, "pick")).to eq(
        ["  def pick(c, x, y)\n    if c\n      y\n    end\n  end\n"]
      )
    end

    it "carries a multi-statement else body over in full" do
      muts = mutations_for("multi_statement_else")

      expect(mutated_bodies(muts, "multi_statement_else")).to eq(
        ["  def multi_statement_else(c, x, y)\n    if c\n      log(y)\n      y\n    end\n  end\n"]
      )
    end

    it "emits nothing for an if without an else" do
      muts = mutations_for("no_else")

      expect(muts).to be_empty
    end

    it "emits nothing for an empty if-branch" do
      muts = mutations_for("empty_then")

      expect(muts).to be_empty
    end

    it "emits nothing for an empty else body" do
      muts = mutations_for("empty_else")

      expect(muts).to be_empty
    end

    it "skips the outer if of an elsif chain, but swaps the elsif's own else" do
      muts = mutations_for("elsif_chain")

      expect(mutated_bodies(muts, "elsif_chain")).to eq(
        ["  def elsif_chain(a, b, x, y, z)\n    if a\n      x\n    elsif b\n      z\n    end\n  end\n"]
      )
    end

    it "descends into a nested if" do
      muts = mutations_for("nested")

      expect(mutated_bodies(muts, "nested")).to eq(
        [
          "  def nested(c, d, x, y, z)\n    if c\n      if d\n        y\n      else\n        " \
          "z\n      end\n    end\n  end\n",
          "  def nested(c, d, x, y, z)\n    if c\n      x\n    else\n      if d\n        " \
          "z\n      end\n    end\n  end\n"
        ]
      )
    end

    it "skips a ternary, whose swap would not parse" do
      muts = mutations_for("ternary")

      expect(muts).to be_empty
    end

    it "reports the mutation on the line of the if" do
      muts = mutations_for("pick")

      expect(muts.map(&:line)).to eq([3])
    end

    it "names the operator" do
      muts = mutations_for("pick")

      expect(muts.map(&:operator_name)).to eq(["if_branch_swap"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("pick") + mutations_for("nested")

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "emits nothing for a method without conditionals" do
      muts = mutations_from_source("def plain(a, b)\n  a + b\nend\n")

      expect(muts).to be_empty
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["if"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#pick") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
