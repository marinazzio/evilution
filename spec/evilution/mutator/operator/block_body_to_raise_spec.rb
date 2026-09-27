# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BlockBodyToRaise do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/block_body_to_raise.rb", __dir__)
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
    Tempfile.create(["block_body_to_raise", ".rb"]) do |tmpfile|
      tmpfile.write(inline_source)
      tmpfile.flush
      Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
    end
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "replaces a brace block body with raise" do
      expect(mutated_lines(mutations_for("brace_block"))).to eq(["items.map { |item| raise }"])
    end

    it "replaces a multi-statement do block body with raise" do
      muts = mutations_for("do_block")

      expect(muts.map(&:mutated_source)).to contain_exactly(
        a_string_including("items.each do |item|\n      raise\n    end")
      )
    end

    it "keeps an ensure clause, which does not swallow the raise" do
      muts = mutations_for("with_ensure")

      expect(muts.map(&:mutated_source)).to contain_exactly(
        a_string_including("items.each do |item|\n      raise\n    ensure\n      flush\n    end")
      )
    end

    it "mutates loop, which the raise ends on its first iteration" do
      muts = mutations_for("kernel_loop")

      expect(muts.map(&:mutated_source)).to contain_exactly(a_string_including("loop do\n      raise\n    end"))
    end

    # Numbered and `it` parameters get the same block-level mutation (EV-27v9.5).
    it "replaces the body of a numbered-parameter block" do
      muts = mutations_from_source("def t(items)\n  items.map { _1.name }\nend\n")

      expect(mutated_lines(muts)).to eq(["items.map { raise }"])
    end

    it "replaces the body of a multi-numbered-parameter block" do
      muts = mutations_from_source("def t(pairs)\n  pairs.map { _1 + _2 }\nend\n")

      expect(mutated_lines(muts)).to eq(["pairs.map { raise }"])
    end

    it "replaces the body of an it-parameter block" do
      muts = mutations_from_source("def t(items)\n  items.map { it.name }\nend\n")

      expect(mutated_lines(muts)).to eq(["items.map { raise }"])
    end

    it "mutates nested blocks independently" do
      muts = mutations_from_source("def t(rows)\n  rows.map { |r| r.map { |c| c * 2 } }\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("rows.map { |r| raise }", "rows.map { |r| r.map { |c| raise } }")
    end

    it "skips a block with a rescue clause, which would swallow the raise" do
      expect(mutations_for("with_rescue")).to be_empty
    end

    it "skips an empty block" do
      expect(mutations_for("empty_block")).to be_empty
    end

    it "skips a block that already only raises" do
      expect(mutations_for("already_raises")).to be_empty
    end

    it "skips a block-pass" do
      expect(mutations_for("block_pass")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("brace_block").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("brace_block").map(&:operator_name).uniq).to eq(["block_body_to_raise"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=map}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#brace_block") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
