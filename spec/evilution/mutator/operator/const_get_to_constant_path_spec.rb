# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ConstGetToConstantPath do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/const_get_to_constant_path.rb", __dir__)
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
    Tempfile.create(["const_get_to_constant_path", ".rb"]) do |tmpfile|
      tmpfile.write(inline_source)
      tmpfile.flush
      Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
    end
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "rewrites const_get with a symbol to a constant path" do
      expect(mutated_lines(mutations_for("plain"))).to eq(["Registry::Handler"])
    end

    it "keeps a namespaced receiver" do
      expect(mutated_lines(mutations_for("namespaced_receiver"))).to eq(["Acme::Plugins::Loader"])
    end

    it "drops a false inherit flag" do
      expect(mutated_lines(mutations_for("without_inherit"))).to eq(["Registry::Handler"])
    end

    it "drops a true inherit flag" do
      expect(mutated_lines(mutations_for("with_inherit"))).to eq(["Registry::Handler"])
    end

    it "drops a nil inherit flag, which const_get treats as false" do
      muts = mutations_from_source("def t\n  Registry.const_get(:Handler, nil)\nend\n")

      expect(mutated_lines(muts)).to eq(["Registry::Handler"])
    end

    it "rewrites on a variable receiver" do
      expect(mutated_lines(mutations_for("variable_receiver"))).to eq(["klass::Config"])
    end

    it "rewrites a receiverless call against self" do
      expect(mutated_lines(mutations_for("receiverless"))).to eq(["self::Handler"])
    end

    it "keeps a method-call receiver unwrapped" do
      muts = mutations_from_source("def t(obj)\n  obj.klass.const_get(:Y)\nend\n")

      expect(mutated_lines(muts)).to eq(["obj.klass::Y"])
    end

    # A receiver in front of `.const_get` is already a primary expression, so
    # its source stays valid in front of `::` without extra parentheses.
    it "keeps a parenthesized receiver as written" do
      muts = mutations_from_source("def t(a, b)\n  (a || b).const_get(:Y)\nend\n")

      expect(mutated_lines(muts)).to eq(["(a || b)::Y"])
    end

    it "rewrites a quoted symbol that is a constant name" do
      muts = mutations_from_source("def t\n  Registry.const_get(:\"Handler\")\nend\n")

      expect(mutated_lines(muts)).to eq(["Registry::Handler"])
    end

    it "rewrites each lookup of a chain" do
      muts = mutations_from_source("def t\n  Registry.const_get(:A).const_get(:B)\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("Registry.const_get(:A)::B", "Registry::A.const_get(:B)")
    end

    it "skips other methods taking a constant-like symbol" do
      expect(mutations_from_source("def t\n  Registry.fetch(:Handler)\nend\n")).to be_empty
    end

    it "skips extra arguments after the inherit flag" do
      expect(mutations_from_source("def t\n  Registry.const_get(:Handler, true, 1)\nend\n")).to be_empty
    end

    it "skips a string name" do
      expect(mutations_for("string_name")).to be_empty
    end

    it "skips a dynamic name" do
      expect(mutations_for("dynamic_name")).to be_empty
    end

    it "skips a symbol that is not a constant name" do
      expect(mutations_for("lowercase_symbol")).to be_empty
    end

    it "skips a nested path symbol" do
      expect(mutations_from_source("def t\n  Object.const_get(:\"A::B\")\nend\n")).to be_empty
    end

    it "skips safe navigation, which a constant path cannot express" do
      expect(mutations_for("safe_navigation")).to be_empty
    end

    it "skips a non-literal inherit flag" do
      expect(mutations_for("dynamic_inherit")).to be_empty
    end

    it "skips a call with a block" do
      expect(mutations_from_source("def t\n  Registry.const_get(:Y) { 1 }\nend\n")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("plain").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("plain").map(&:operator_name).uniq).to eq(["const_get_to_constant_path"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=const_get}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#plain") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
