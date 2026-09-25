# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ArgumentPropagation do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/argument_propagation.rb", __dir__)
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
    tmpfile = Tempfile.new(["argument_propagation", ".rb"])
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
    it "replaces an implicit-self call with its only argument" do
      expect(mutated_lines(mutations_for("bare"))).to eq(["value"])
    end

    it "replaces a call with a receiver with its only argument" do
      expect(mutated_lines(mutations_for("with_receiver"))).to eq(["value"])
    end

    it "handles a call without parentheses" do
      expect(mutated_lines(mutations_for("without_parens"))).to eq(["value"])
    end

    it "drops the block along with the call" do
      expect(mutated_lines(mutations_for("with_block"))).to eq(["items"])
    end

    it "promotes at each level of nested calls" do
      expect(mutated_lines(mutations_for("nested"))).to contain_exactly("inner(value)", "outer(value)")
    end

    it "skips a call with two arguments" do
      expect(mutations_for("two_arguments")).to be_empty
    end

    it "skips a call without arguments" do
      expect(mutations_for("no_arguments")).to be_empty
    end

    it "skips a keyword-only argument" do
      expect(mutations_for("keyword_only")).to be_empty
    end

    it "skips a splat argument" do
      expect(mutations_for("splat")).to be_empty
    end

    it "skips a splat argument in value position, where the bare splat would still parse" do
      expect(mutations_from_source("def pack(values)\n  @all = combine(*values)\nend\n")).to be_empty
    end

    it "skips a keyword-only argument nested in another call, where it would still parse" do
      muts = mutations_from_source("def wrapped\n  wrap(build(name: 1))\nend\n")

      expect(mutated_lines(muts)).to eq(["build(name: 1)"])
    end

    it "skips a forwarded argument list nested in another call" do
      muts = mutations_from_source("def relay(...)\n  wrap(target(...))\nend\n")

      expect(mutated_lines(muts)).to eq(["target(...)"])
    end

    it "skips a block-pass argument" do
      expect(mutations_for("block_argument")).to be_empty
    end

    it "skips a forwarded argument list" do
      expect(mutations_from_source("def relay(...)\n  target(...)\nend\n")).to be_empty
    end

    it "skips operator methods, which binary operand promotion covers" do
      expect(mutations_for("binary")).to be_empty
    end

    it "skips an index read" do
      expect(mutations_for("index_read")).to be_empty
    end

    it "skips an attribute write, which attribute_write_to_read covers" do
      expect(mutations_for("attribute_write")).to be_empty
    end

    it "skips a call in void statement position, which statement_deletion covers" do
      expect(mutations_for("void_statement")).to be_empty
    end

    it "still mutates a call that is the last statement of a body" do
      muts = mutations_from_source("def run(a, v)\n  a.prepare\n  a.finish(v)\nend\n")

      expect(mutated_lines(muts)).to eq(["v"])
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("bare").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("bare").map(&:operator_name).uniq).to eq(["argument_propagation"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=normalize}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#bare") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
