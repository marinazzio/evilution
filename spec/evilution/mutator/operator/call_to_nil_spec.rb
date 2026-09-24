# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::CallToNil do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/call_to_nil.rb", __dir__)
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
    tmpfile = Tempfile.new(["call_to_nil", ".rb"])
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
    it "replaces an implicit-self call with nil" do
      expect(mutated_lines(mutations_for("bare_call"))).to eq(["nil"])
    end

    it "replaces a call with a receiver with nil" do
      expect(mutated_lines(mutations_for("with_receiver"))).to eq(["nil"])
    end

    it "replaces a call with arguments with nil" do
      expect(mutated_lines(mutations_for("with_arguments"))).to eq(["nil"])
    end

    it "replaces a predicate call with nil" do
      expect(mutated_lines(mutations_for("predicate"))).to eq(["nil"])
    end

    it "replaces a call carrying a block, block included" do
      expect(mutated_lines(mutations_for("with_block"))).to eq(["nil"])
    end

    it "replaces the outer call of a chain but not the receiver calls" do
      expect(mutated_lines(mutations_for("chained"))).to eq(["nil"])
    end

    it "replaces a binary operator call" do
      expect(mutated_lines(mutations_for("binary"))).to eq(["nil"])
    end

    it "replaces a call in value position of an assignment" do
      expect(mutated_lines(mutations_for("assigned"))).to eq(["name = nil"])
    end

    it "replaces a call nested as an argument of another call" do
      expect(mutated_lines(mutations_for("nested_argument"))).to contain_exactly("nil", "render(nil)")
    end

    it "descends into block bodies" do
      muts = mutations_from_source("def each_name(items)\n  items.map { |i| i.name }\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("nil", "items.map { |i| nil }")
    end

    it "skips a call in void statement position, which statement_deletion covers" do
      expect(mutated_lines(mutations_for("void_statement"))).to be_empty
    end

    it "still mutates a call that is the last statement of a body" do
      muts = mutations_from_source("def run(a)\n  a.prepare\n  a.finish\nend\n")

      expect(mutated_lines(muts)).to eq(["nil"])
      expect(muts.map(&:line)).to eq([3])
    end

    it "keeps identical statements apart, mutating only the last one" do
      muts = mutations_from_source("def twice(a)\n  a.run\n  a.run\nend\n")

      expect(muts.map(&:line)).to eq([3])
    end

    it "skips an attribute write" do
      expect(mutations_for("attribute_write")).to be_empty
    end

    it "skips an index write" do
      expect(mutations_for("index_write")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("with_receiver").map(&:line)).to eq([7])
    end

    it "names the operator" do
      expect(mutations_for("with_receiver").map(&:operator_name).uniq).to eq(["call_to_nil"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "emits nothing for a method without calls" do
      expect(mutations_from_source("def plain(a)\n  a\nend\n")).to be_empty
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=name}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#with_receiver") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
