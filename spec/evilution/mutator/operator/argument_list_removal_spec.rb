# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ArgumentListRemoval do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/argument_list_removal.rb", __dir__)
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
    tmpfile = Tempfile.new(["argument_list_removal", ".rb"])
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
    it "drops every argument of a call" do
      expect(mutated_lines(mutations_for("several"))).to eq(["combine"])
    end

    it "drops a single argument" do
      expect(mutated_lines(mutations_for("single"))).to eq(["normalize"])
    end

    it "keeps the receiver" do
      expect(mutated_lines(mutations_for("with_receiver"))).to eq(["formatter.format"])
    end

    it "handles a call without parentheses" do
      expect(mutated_lines(mutations_for("without_parens"))).to eq(["puts"])
    end

    it "drops keyword arguments" do
      expect(mutated_lines(mutations_for("keywords"))).to eq(["build"])
    end

    it "drops a splat argument" do
      expect(mutated_lines(mutations_for("splat"))).to eq(["combine"])
    end

    it "drops a forwarded argument list" do
      expect(mutated_lines(mutations_from_source("def relay(...)\n  target(...)\nend\n"))).to eq(["target"])
    end

    it "keeps a block-pass argument" do
      expect(mutated_lines(mutations_for("block_pass"))).to eq(["items.each_slice(&block)"])
    end

    it "keeps a block-pass argument on a call without parentheses" do
      expect(mutated_lines(mutations_for("block_pass_without_parens"))).to eq(["items.each_slice(&block)"])
    end

    it "keeps a literal block" do
      expect(mutated_lines(mutations_for("literal_block"))).to eq(["items.each_slice { |pair| pair }"])
    end

    it "keeps a do-block on a call without parentheses" do
      muts = mutations_from_source("def pairs(items)\n  items.each_slice 2 do |pair|\n    pair\n  end\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def pairs(items)\n  items.each_slice do |pair|\n    pair\n  end\nend\n"])
    end

    it "mutates a call in void statement position" do
      expect(mutated_lines(mutations_for("void_statement"))).to eq(["logger.info"])
    end

    it "drops a heredoc argument together with its body" do
      muts = mutations_from_source("def say\n  emit(<<~TXT)\n    hi\n  TXT\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def say\n  emit\nend\n"])
    end

    it "mutates nested calls independently" do
      muts = mutations_from_source("def nest(v)\n  outer(inner(v))\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("outer", "outer(inner)")
    end

    it "skips a call whose only argument is a block-pass" do
      expect(mutations_for("only_block_pass")).to be_empty
    end

    it "skips a call without arguments" do
      expect(mutations_for("no_arguments")).to be_empty
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

    it "skips the .() call shorthand" do
      expect(mutations_for("call_shorthand")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("several").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("several").map(&:operator_name).uniq).to eq(["argument_list_removal"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=combine}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#several") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
