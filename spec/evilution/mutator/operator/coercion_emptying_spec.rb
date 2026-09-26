# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::CoercionEmptying do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/coercion_emptying.rb", __dir__)
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
    tmpfile = Tempfile.new(["coercion_emptying", ".rb"])
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
    it "empties to_a" do
      expect(mutated_lines(mutations_for("array"))).to eq(["[]"])
    end

    it "empties to_ary" do
      expect(mutated_lines(mutations_for("implicit_array"))).to eq(["[]"])
    end

    it "empties to_h" do
      expect(mutated_lines(mutations_for("hash"))).to eq(["{}"])
    end

    it "empties to_hash" do
      expect(mutated_lines(mutations_for("implicit_hash"))).to eq(["{}"])
    end

    it "empties to_s" do
      expect(mutated_lines(mutations_for("string"))).to eq(['""'])
    end

    it "empties to_str" do
      expect(mutated_lines(mutations_for("implicit_string"))).to eq(['""'])
    end

    it "empties a safe-navigation call" do
      expect(mutated_lines(mutations_for("safe_navigation"))).to eq(['""'])
    end

    # `render {}` would pass a block, not an empty hash.
    it "parenthesizes an empty hash that is the first argument of a call without parentheses" do
      expect(mutated_lines(mutations_for("bare_argument"))).to eq(["render ({})"])
    end

    it "keeps a plain empty hash inside parentheses" do
      expect(mutated_lines(mutations_for("parenthesized_argument"))).to eq(["render({})"])
    end

    it "keeps a plain empty hash for a later argument of a call without parentheses" do
      muts = mutations_from_source("def t(a, v)\n  render a, v.to_h\nend\n")

      expect(mutated_lines(muts)).to eq(["render a, {}"])
    end

    it "parenthesizes an empty hash passed to yield without parentheses" do
      muts = mutations_from_source("def t(v)\n  yield v.to_h\nend\n")

      expect(mutated_lines(muts)).to eq(["yield ({})"])
    end

    it "parenthesizes an empty hash passed to super without parentheses" do
      muts = mutations_from_source("class A < B\n  def t(v)\n    super v.to_h\n  end\nend\n")

      expect(mutated_lines(muts)).to eq(["super ({})"])
    end

    it "keeps a plain empty hash passed to yield with parentheses" do
      muts = mutations_from_source("def t(v)\n  yield(v.to_h)\nend\n")

      expect(mutated_lines(muts)).to eq(["yield({})"])
    end

    it "keeps a plain empty hash passed to super with parentheses" do
      muts = mutations_from_source("class A < B\n  def t(v)\n    super(v.to_h)\n  end\nend\n")

      expect(mutated_lines(muts)).to eq(["super({})"])
    end

    it "leaves an empty string or array unwrapped as a bare first argument" do
      muts = mutations_from_source("def t(v)\n  render v.to_s\n  render v.to_a\nend\n")

      expect(mutated_lines(muts)).to contain_exactly('render ""', "render []")
    end

    it "skips other methods" do
      expect(mutations_from_source("def t(v)\n  v.name\nend\n")).to be_empty
    end

    it "skips a call with arguments" do
      expect(mutations_for("with_base")).to be_empty
    end

    it "skips a call with a block" do
      expect(mutations_for("with_block")).to be_empty
    end

    it "skips a call with a block-pass" do
      expect(mutations_from_source("def t(v, b)\n  v.to_h(&b)\nend\n")).to be_empty
    end

    it "skips a nil receiver, whose conversion is already empty" do
      expect(mutations_for("nil_receiver")).to be_empty
    end

    it "skips a receiverless call" do
      expect(mutations_for("receiverless")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("array").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("array").map(&:operator_name).uniq).to eq(["coercion_emptying"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=to_a}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#array") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
