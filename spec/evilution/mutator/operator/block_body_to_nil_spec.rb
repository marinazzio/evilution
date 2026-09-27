# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BlockBodyToNil do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/block_body_to_nil.rb", __dir__)
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
    Tempfile.create(["block_body_to_nil", ".rb"]) do |tmpfile|
      tmpfile.write(inline_source)
      tmpfile.flush
      Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
    end
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "replaces a brace block body with nil" do
      expect(mutated_lines(mutations_for("brace_block"))).to eq(["items.map { |item| nil }"])
    end

    it "replaces a multi-statement do block body with nil" do
      muts = mutations_for("do_block")

      expect(muts.map(&:mutated_source)).to contain_exactly(
        a_string_including("items.each do |item|\n      nil\n    end")
      )
    end

    it "keeps a rescue clause, emptying only the main statements" do
      muts = mutations_for("with_rescue")

      expect(muts.map(&:mutated_source)).to contain_exactly(
        a_string_including("items.each do |item|\n      nil\n    rescue StandardError\n      skip(item)\n    end")
      )
    end

    it "mutates a lambda block" do
      expect(mutated_lines(mutations_for("lambda_block"))).to eq(["lambda { |x| nil }"])
    end

    it "mutates a bounded cycle" do
      expect(mutated_lines(mutations_for("bounded_cycle"))).to eq(["items.cycle(2) { |item| nil }"])
    end

    it "mutates nested blocks independently" do
      muts = mutations_from_source("def t(rows)\n  rows.map { |r| r.map { |c| c * 2 } }\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("rows.map { |r| nil }", "rows.map { |r| r.map { |c| nil } }")
    end

    it "skips an empty block" do
      expect(mutations_for("empty_block")).to be_empty
    end

    it "skips a block whose body is already nil" do
      expect(mutations_for("nil_block")).to be_empty
    end

    it "skips loop, whose nil body would never terminate" do
      expect(mutations_for("kernel_loop")).to be_empty
    end

    it "skips Kernel.loop" do
      expect(mutations_from_source("def t(q)\n  Kernel.loop { q.pop }\nend\n")).to be_empty
    end

    it "skips ::Kernel.loop" do
      expect(mutations_from_source("def t(q)\n  ::Kernel.loop { q.pop }\nend\n")).to be_empty
    end

    it "still mutates loop on another top-level constant" do
      muts = mutations_from_source("def t\n  ::Worker.loop { step }\nend\n")

      expect(mutated_lines(muts)).to eq(["::Worker.loop { nil }"])
    end

    it "still mutates loop on a namespaced Kernel constant" do
      muts = mutations_from_source("def t\n  Acme::Kernel.loop { step }\nend\n")

      expect(mutated_lines(muts)).to eq(["Acme::Kernel.loop { nil }"])
    end

    it "still mutates loop called on another receiver" do
      muts = mutations_from_source("def t(runner)\n  runner.loop { step }\nend\n")

      expect(mutated_lines(muts)).to eq(["runner.loop { nil }"])
    end

    it "still mutates loop called on another constant" do
      muts = mutations_from_source("def t\n  Worker.loop { step }\nend\n")

      expect(mutated_lines(muts)).to eq(["Worker.loop { nil }"])
    end

    it "still mutates loop on a method call that happens to be named Kernel" do
      muts = mutations_from_source("def t(x)\n  x.Kernel.loop { step }\nend\n")

      expect(mutated_lines(muts)).to eq(["x.Kernel.loop { nil }"])
    end

    it "skips cycle without a count, whose nil body would never terminate" do
      expect(mutations_for("endless_cycle")).to be_empty
    end

    it "skips cycle(nil), which Ruby treats as endless" do
      expect(mutations_from_source("def t(xs)\n  xs.cycle(nil) { |x| process(x) }\nend\n")).to be_empty
    end

    it "skips a block-pass" do
      expect(mutations_for("block_pass")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("brace_block").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("brace_block").map(&:operator_name).uniq).to eq(["block_body_to_nil"])
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
