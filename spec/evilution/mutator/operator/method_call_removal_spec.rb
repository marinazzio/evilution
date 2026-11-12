# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::MethodCallRemoval do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/method_call.rb", __dir__) }
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
    Tempfile.create(["method_call_removal", ".rb"]) do |tmpfile|
      tmpfile.write(inline_source)
      tmpfile.flush
      Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
    end
  end

  def mutated_lines_from_source(inline_source)
    mutations_from_source(inline_source).map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    it "replaces receiver.method with receiver" do
      muts = mutations_for("no_args")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("obj\n")
      expect(muts.first.mutated_source).not_to include("obj.save")
    end

    it "replaces receiver.method(args) with receiver" do
      muts = mutations_for("with_args")

      replacements = muts.map(&:mutated_source)
      expect(replacements.any? { |s| s.include?("obj\n") && !s.include?("obj.compute") }).to be true
    end

    it "handles chained calls by removing each link" do
      muts = mutations_for("chained")

      # items.select(&:valid?).first → items.select(&:valid?)  (remove .first)
      # items.select(&:valid?).first → items.first              (remove .select, keep outer .first)
      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?("items.select(&:valid?)\n") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("items.first") }).to be true
    end

    it "skips calls without a receiver" do
      muts = mutations_for("without_receiver")

      expect(muts).to be_empty
    end

    it "replaces self.method with self" do
      muts = mutations_for("with_self")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("self\n")
      expect(muts.first.mutated_source).not_to include("self.name")
    end

    # Dropping `.lazy` from a chain is how this operator probes laziness
    # assumptions: the chain turns eager, so an infinite source hangs (and is
    # classified as a timeout) and a large one is built in full. A separate
    # operator for the same edit was proposed and dropped in favour of these
    # cases.
    it "drops .lazy from an enumerator chain" do
      lines = mutated_lines_from_source("def t(items)\n  items.lazy.select(&:even?).first(3)\nend\n")

      expect(lines).to include("items.select(&:even?).first(3)")
    end

    it "drops .lazy from a chain over an infinite range" do
      lines = mutated_lines_from_source("def t\n  (1..Float::INFINITY).lazy.map { _1 * 2 }.first(5)\nend\n")

      expect(lines).to include("(1..Float::INFINITY).map { _1 * 2 }.first(5)")
    end

    it "drops .lazy from a chain ending in force" do
      lines = mutated_lines_from_source("def t(items)\n  items.lazy.map(&:to_s).force\nend\n")

      expect(lines).to include("items.map(&:to_s).force")
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "Invalid Ruby produced for #{mutation}: #{result.errors.map(&:message)}"
        end
      end
    end

    context "with a constant's value" do
      def constant_lines(inline_source)
        mutations_from_source(inline_source).select { |m| m.subject.kind == :constant_write }
                                            .map { |m| m.mutated_source.lines[m.line - 1].strip }
      end

      it "runs on constant-write subjects as well as the default kinds" do
        expect(described_class.subject_kinds).to eq(%i[method scope aasm callback constant_write])
      end

      it "replaces a call in the value with its receiver" do
        expect(constant_lines("class C\n  LIMIT = ENV[\"X\"].to_i\nend\n"))
          .to contain_exactly("LIMIT = ENV[\"X\"]", "LIMIT = ENV.to_i")
      end

      it "leaves the value's freeze to freeze_removal" do
        expect(constant_lines("class C\n  NAMES = names.map(&:to_s).freeze\nend\n"))
          .to contain_exactly("NAMES = names.freeze")
      end

      it "still drops a freeze that takes arguments" do
        expect(constant_lines("class C\n  X = a.freeze(1)\nend\n")).to contain_exactly("X = a")
      end

      it "leaves a method defined in the value to that method's own subject" do
        expect(constant_lines("class C\n  H = Class.new do\n    def go(a) = a.to_i\n  end\nend\n"))
          .to contain_exactly("H = Class")
      end

      it "drops freeze in a method body as before" do
        expect(mutated_lines_from_source("def t\n  x.freeze\nend\n")).to include("x")
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("no_args")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("method_call_removal")
      end
    end
  end
end
