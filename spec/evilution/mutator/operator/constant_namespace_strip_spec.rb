# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ConstantNamespaceStrip do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/constant_namespace_strip.rb", __dir__)
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

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "strips the namespace off a constant path" do
      expect(mutated_lines(mutations_for("constant_path"))).to eq(["LIMIT"])
    end

    it "strips a nested path at each level" do
      expect(mutated_lines(mutations_for("nested_constant_path"))).to contain_exactly("LIMIT", "Config::LIMIT")
    end

    it "strips the namespace off a call receiver" do
      expect(mutated_lines(mutations_for("call_receiver"))).to eq(["Builder.new"])
    end

    it "strips the namespace off a constant passed as an argument" do
      expect(mutated_lines(mutations_for("as_argument"))).to eq(["value.is_a?(Timeout)"])
    end

    it "strips the namespace in value position of an assignment" do
      expect(mutated_lines(mutations_for("assigned"))).to eq(["limit = LIMIT"])
    end

    it "strips the namespace off a rescued exception class" do
      expect(mutated_lines(mutations_for("rescue_class"))).to eq(["rescue Timeout"])
    end

    it "strips a namespace given by an expression" do
      expect(mutated_lines(mutations_for("dynamic_namespace"))).to eq(["LIMIT"])
    end

    it "strips an anchored namespace whole, anchor included" do
      expect(mutated_lines(mutations_for("anchored_namespace"))).to eq(["LIMIT"])
    end

    it "skips a top-level path, which has no namespace" do
      expect(mutations_for("top_level_path")).to be_empty
    end

    it "skips a bare constant" do
      expect(mutations_for("bare_constant")).to be_empty
    end

    it "skips a namespaced method call" do
      expect(mutations_for("namespaced_call")).to be_empty
    end

    it "skips the target of a constant path or-write, a dynamic constant assignment once bare" do
      expect(mutations_for("path_or_write")).to be_empty
    end

    it "still strips a path in the value of a constant path or-write" do
      expect(mutated_lines(mutations_for("path_write_value"))).to eq(["Config::LIMIT ||= LIMIT"])
    end

    it "strips the value but not the target of a constant path and-write" do
      expect(mutated_lines(mutations_for("path_and_write"))).to eq(["Config::LIMIT &&= LIMIT"])
    end

    it "strips the value but not the target of a constant path operator write" do
      expect(mutated_lines(mutations_for("path_operator_write"))).to eq(["Config::LIMIT += STEP"])
    end

    it "reports the mutation on the line of the constant path" do
      expect(mutations_for("constant_path").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("constant_path").map(&:operator_name).uniq).to eq(["constant_namespace_strip"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["constant_path"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#constant_path") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
