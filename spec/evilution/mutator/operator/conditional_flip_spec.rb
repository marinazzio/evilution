# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ConditionalFlip do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/conditional_flip.rb", __dir__) }
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
    it "flips if to unless" do
      muts = mutations_for("simple_if")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("unless x > 0\n      \"positive\"")
    end

    it "flips unless to if" do
      muts = mutations_for("simple_unless")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("if x > 0\n      \"non-positive\"")
    end

    it "flips if/else to unless/else" do
      muts = mutations_for("if_else")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("unless x > 0\n      \"positive\"")
    end

    it "flips unless/else to if/else" do
      muts = mutations_for("unless_else")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("if x > 0\n      \"non-positive\"")
    end

    it "flips modifier if to modifier unless" do
      muts = mutations_for("modifier_if")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('return "positive" unless x > 0')
    end

    it "flips modifier unless to modifier if" do
      muts = mutations_for("modifier_unless")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('return "non-positive" if x > 0')
    end

    it "skips ternary expressions" do
      muts = mutations_for("ternary")

      expect(muts).to be_empty
    end

    it "skips if with elsif branches" do
      muts = mutations_for("with_elsif")

      expect(muts).to be_empty
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
      muts = mutations_for("simple_if")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("conditional_flip")
      end
    end
  end
end
