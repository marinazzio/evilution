# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ProcToLambda do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/proc_to_lambda.rb", __dir__)
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
    Tempfile.create(["proc_to_lambda", ".rb"]) do |tmpfile|
      tmpfile.write(inline_source)
      tmpfile.flush
      Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
    end
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "rewrites proc with a brace block to lambda" do
      expect(mutated_lines(mutations_for("kernel_proc"))).to eq(["lambda { |a, b| [a, b] }"])
    end

    it "rewrites proc with a do block to lambda" do
      muts = mutations_for("kernel_proc_do")

      expect(muts.map(&:mutated_source)).to contain_exactly(a_string_including("    lambda do |value|\n      value\n    end"))
    end

    it "rewrites Proc.new to lambda" do
      expect(mutated_lines(mutations_for("proc_new"))).to eq(["lambda { |value| value }"])
    end

    it "rewrites ::Proc.new to lambda" do
      expect(mutated_lines(mutations_for("top_level_proc_new"))).to eq(["lambda { :ok }"])
    end

    it "drops empty parentheses along with the head" do
      muts = mutations_from_source("def t\n  Proc.new() { 1 }\nend\n")

      expect(mutated_lines(muts)).to eq(["lambda { 1 }"])
    end

    it "rewrites a proc nested in another proc's block" do
      muts = mutations_from_source("def t\n  proc { proc { 1 } }\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("lambda { proc { 1 } }", "proc { lambda { 1 } }")
    end

    it "skips a block-pass" do
      expect(mutations_for("block_pass")).to be_empty
    end

    it "skips an existing lambda" do
      expect(mutations_for("already_lambda")).to be_empty
    end

    it "skips new on another receiver" do
      expect(mutations_for("other_receiver")).to be_empty
    end

    it "skips proc called on a receiver" do
      expect(mutations_from_source("def t(obj)\n  obj.proc { 1 }\nend\n")).to be_empty
    end

    it "skips a call with arguments" do
      expect(mutations_from_source("def t(x)\n  Proc.new(x) { 1 }\nend\n")).to be_empty
    end

    it "skips new on another top-level constant" do
      expect(mutations_from_source("def t\n  ::Handler.new { 1 }\nend\n")).to be_empty
    end

    it "skips new on a variable receiver" do
      expect(mutations_from_source("def t(klass)\n  klass.new { 1 }\nend\n")).to be_empty
    end

    it "skips a namespaced Proc constant" do
      expect(mutations_from_source("def t\n  Foo::Proc.new { 1 }\nend\n")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("kernel_proc").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("kernel_proc").map(&:operator_name).uniq).to eq(["proc_to_lambda"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=proc}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#kernel_proc") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
