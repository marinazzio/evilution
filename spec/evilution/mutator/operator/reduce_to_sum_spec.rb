# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ReduceToSum do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/reduce_to_sum.rb", __dir__)
  end
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

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["reduce_to_sum", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "rewrites reduce(:+) to sum" do
      expect(mutated_lines(mutations_for("reduce_symbol"))).to eq(["values.sum"])
    end

    it "rewrites inject(:+) to sum" do
      expect(mutated_lines(mutations_for("inject_symbol"))).to eq(["values.sum"])
    end

    it "carries an initial value into sum" do
      expect(mutated_lines(mutations_for("with_initial"))).to eq(["values.sum(10)"])
    end

    it "rewrites the block-pass form" do
      expect(mutated_lines(mutations_for("block_pass"))).to eq(["values.sum"])
    end

    it "rewrites the block-pass form with an initial value" do
      expect(mutated_lines(mutations_for("block_pass_with_initial"))).to eq(["values.sum(0)"])
    end

    it "handles a call without parentheses" do
      expect(mutated_lines(mutations_for("without_parens"))).to eq(["values.sum"])
    end

    it "keeps safe navigation" do
      expect(mutated_lines(mutations_for("safe_navigation"))).to eq(["values&.sum"])
    end

    it "keeps a compound initial value intact" do
      muts = mutations_from_source("def t(values, base)\n  values.inject(base * 2, :+)\nend\n")

      expect(mutated_lines(muts)).to eq(["values.sum(base * 2)"])
    end

    it "handles a block-pass without parentheses" do
      muts = mutations_from_source("def t(values)\n  values.inject 0, &:+\nend\n")

      expect(mutated_lines(muts)).to eq(["values.sum(0)"])
    end

    it "rewrites a reduction nested in a block" do
      muts = mutations_from_source("def t(rows)\n  rows.map { |row| row.reduce(:+) }\nend\n")

      expect(mutated_lines(muts)).to eq(["rows.map { |row| row.sum }"])
    end

    it "skips more than one value before :+" do
      expect(mutations_from_source("def t(values)\n  values.reduce(1, 2, :+)\nend\n")).to be_empty
    end

    it "skips another operator symbol" do
      expect(mutations_for("other_operator")).to be_empty
    end

    it "skips a literal block" do
      expect(mutations_for("literal_block")).to be_empty
    end

    it "skips another method taking :+" do
      expect(mutations_for("other_method")).to be_empty
    end

    it "skips reduce without arguments" do
      expect(mutations_for("no_arguments")).to be_empty
    end

    it "skips an implicit receiver" do
      expect(mutations_for("implicit_receiver")).to be_empty
    end

    it "skips a block-pass that is not :+" do
      expect(mutations_from_source("def t(values)\n  values.reduce(&:*)\nend\n")).to be_empty
    end

    it "skips a symbol and a block-pass together" do
      expect(mutations_from_source("def t(values, blk)\n  values.reduce(:+, &blk)\nend\n")).to be_empty
    end

    # `:+` is then the initial value, not the operator, and both the original
    # and `sum(:+)` raise NoMethodError — an unkillable mutant.
    it "skips :+ passed both as an argument and as a block-pass" do
      expect(mutations_from_source("def t(values)\n  values.reduce(:+, &:+)\nend\n")).to be_empty
    end

    it "skips a splat argument" do
      expect(mutations_from_source("def t(values, args)\n  values.reduce(*args, :+)\nend\n")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("reduce_symbol").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("reduce_symbol").map(&:operator_name).uniq).to eq(["reduce_to_sum"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=reduce}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#reduce_symbol") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
