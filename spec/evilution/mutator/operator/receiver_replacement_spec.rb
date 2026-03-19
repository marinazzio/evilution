# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ReceiverReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/receiver_replacement.rb", __dir__) }
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

  describe "#call" do
    it "drops self from self.method" do
      muts = mutations_for("with_self")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("  def with_self\n    name\n  end")
    end

    it "drops self from self.method(args)" do
      muts = mutations_for("self_with_args")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("compute(x)")
      expect(muts.first.mutated_source).not_to include("self.compute")
    end

    it "drops self from self.method with block" do
      muts = mutations_for("self_with_block")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("tap { |x| x }")
      expect(muts.first.mutated_source).not_to include("self.tap")
    end

    it "skips calls with non-self receiver" do
      muts = mutations_for("no_self")

      expect(muts).to be_empty
    end

    it "skips calls without explicit receiver" do
      muts = mutations_for("implicit_self")

      expect(muts).to be_empty
    end

    it "drops self from self.setter=" do
      muts = mutations_for("self_setter")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("  def self_setter(val)\n    name = val\n  end")
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

    it "sets correct operator_name" do
      muts = mutations_for("with_self")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("receiver_replacement")
      end
    end
  end
end
