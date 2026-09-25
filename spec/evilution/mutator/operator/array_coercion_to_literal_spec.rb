# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ArrayCoercionToLiteral do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/array_coercion_to_literal.rb", __dir__)
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
    tmpfile = Tempfile.new(["array_coercion_to_literal", ".rb"])
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
    it "rewrites Array(x) to [x]" do
      expect(mutated_lines(mutations_for("implicit"))).to eq(["[value]"])
    end

    it "rewrites Kernel.Array(x)" do
      expect(mutated_lines(mutations_for("kernel_dot"))).to eq(["[value]"])
    end

    it "rewrites Kernel::Array(x)" do
      expect(mutated_lines(mutations_for("kernel_colons"))).to eq(["[value]"])
    end

    it "rewrites ::Kernel.Array(x)" do
      muts = mutations_from_source("def t(v)\n  ::Kernel.Array(v)\nend\n")

      expect(mutated_lines(muts)).to eq(["[v]"])
    end

    it "handles a call without parentheses" do
      expect(mutated_lines(mutations_for("without_parens"))).to eq(["[value]"])
    end

    it "keeps a compound argument intact" do
      expect(mutated_lines(mutations_for("compound_argument"))).to eq(["[options[:ids]]"])
    end

    it "rewrites a coercion nested in another call" do
      muts = mutations_from_source("def t(v)\n  wrap(Array(v))\nend\n")

      expect(mutated_lines(muts)).to eq(["wrap([v])"])
    end

    # Array(a: 1) is [[:a, 1]], while [a: 1] wraps the hash: [{a: 1}].
    it "rewrites a keyword-hash argument, which Array() converts but the literal wraps" do
      muts = mutations_from_source("def t\n  Array(a: 1)\nend\n")

      expect(mutated_lines(muts)).to eq(["[a: 1]"])
    end

    it "skips a constant receiver other than Kernel" do
      expect(mutations_for("other_receiver")).to be_empty
    end

    it "skips a variable receiver" do
      expect(mutations_from_source("def t(obj, v)\n  obj.Array(v)\nend\n")).to be_empty
    end

    it "skips a namespaced Kernel constant" do
      expect(mutations_from_source("def t(v)\n  Foo::Kernel.Array(v)\nend\n")).to be_empty
    end

    it "skips a top-level constant other than Kernel" do
      expect(mutations_from_source("def t(v)\n  ::Converter.Array(v)\nend\n")).to be_empty
    end

    it "skips a splat argument" do
      expect(mutations_for("splat")).to be_empty
    end

    it "skips a call without arguments" do
      expect(mutations_for("no_argument")).to be_empty
    end

    it "skips other Kernel coercions" do
      expect(mutations_for("other_method")).to be_empty
    end

    it "skips a call with a block" do
      expect(mutations_from_source("def t(v)\n  Array(v) { 1 }\nend\n")).to be_empty
    end

    it "skips a call with a block-pass" do
      expect(mutations_from_source("def t(v, b)\n  Array(v, &b)\nend\n")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("implicit").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("implicit").map(&:operator_name).uniq).to eq(["array_coercion_to_literal"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=Array}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#implicit") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
