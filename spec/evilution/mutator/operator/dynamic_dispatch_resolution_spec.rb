# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::DynamicDispatchResolution do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/dynamic_dispatch_resolution.rb", __dir__)
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
    tmpfile = Tempfile.new(["dynamic_dispatch_resolution", ".rb"])
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
    it "resolves send on an explicit receiver to a direct call" do
      expect(mutated_lines(mutations_for("explicit_send"))).to eq(["target.reset"])
    end

    it "keeps the remaining arguments" do
      expect(mutated_lines(mutations_for("send_with_arguments"))).to eq(["target.update(a, b)"])
    end

    it "resolves __send__" do
      expect(mutated_lines(mutations_for("underscore_send"))).to eq(["target.reset"])
    end

    it "handles send without parentheses" do
      expect(mutated_lines(mutations_for("send_without_parens"))).to eq(["target.store value"])
    end

    it "keeps a block-pass argument" do
      expect(mutated_lines(mutations_for("send_with_block_pass"))).to eq(["target.each(&block)"])
    end

    it "keeps a literal block" do
      expect(mutated_lines(mutations_for("send_with_literal_block"))).to eq(["target.each { |item| item }"])
    end

    it "keeps safe navigation" do
      expect(mutated_lines(mutations_for("safe_send"))).to eq(["target&.reset"])
    end

    it "resolves public_send with an implicit receiver" do
      expect(mutated_lines(mutations_for("implicit_public_send"))).to eq(["store(value)"])
    end

    it "resolves public_send on self" do
      expect(mutated_lines(mutations_for("self_public_send"))).to eq(["self.reset"])
    end

    it "handles send without parentheses and without further arguments" do
      muts = mutations_from_source("def go(t)\n  t.send :reset\n  t\nend\n")

      expect(mutated_lines(muts)).to eq(["t.reset"])
    end

    it "keeps a do-block on send without parentheses" do
      muts = mutations_from_source("def walk(t)\n  t.send :each do |x|\n    x\n  end\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def walk(t)\n  t.each do |x|\n    x\n  end\nend\n"])
    end

    it "resolves a dispatch nested in another dispatch's arguments" do
      muts = mutations_from_source("def relay(a, b)\n  a.send(:put, b.send(:get))\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("a.put(b.send(:get))", "a.send(:put, b.get)")
    end

    it "skips an ordinary implicit call with a symbol argument" do
      expect(mutations_from_source("def pick\n  helper(:name)\nend\n")).to be_empty
    end

    it "resolves an operator selector" do
      muts = mutations_from_source("def add(a, b)\n  a.send(:+, b)\nend\n")

      expect(mutated_lines(muts)).to eq(["a.+(b)"])
    end

    it "skips a selector that is not a valid method name after a dot" do
      expect(mutations_from_source("def odd(t)\n  t.send(:\"not a name\")\nend\n")).to be_empty
    end

    it "skips send with an implicit receiver, where private methods resolve the same" do
      expect(mutations_for("implicit_send")).to be_empty
    end

    it "skips send on self, where private methods resolve the same" do
      expect(mutations_for("self_send")).to be_empty
    end

    it "skips public_send on an explicit receiver, where visibility checks match" do
      expect(mutations_for("explicit_public_send")).to be_empty
    end

    it "skips a string selector" do
      expect(mutations_for("string_selector")).to be_empty
    end

    it "skips a dynamic selector" do
      expect(mutations_for("dynamic_selector")).to be_empty
    end

    it "skips a splat selector" do
      expect(mutations_for("splat_selector")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("explicit_send").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("explicit_send").map(&:operator_name).uniq).to eq(["dynamic_dispatch_resolution"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=send}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#explicit_send") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
