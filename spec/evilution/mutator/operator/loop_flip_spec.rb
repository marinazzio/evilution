# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::LoopFlip do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/loop_flip.rb", __dir__) }
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
    it "flips while to until" do
      muts = mutations_for("simple_while")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("until x > 0")
    end

    it "flips until to while" do
      muts = mutations_for("simple_until")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("while x > 0")
    end

    it "flips modifier while to modifier until" do
      muts = mutations_for("modifier_while")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("x -= 1 until x > 0")
    end

    it "flips modifier until to modifier while" do
      muts = mutations_for("modifier_until")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("x += 1 while x > 0")
    end

    it "flips while in complex method bodies" do
      muts = mutations_for("while_with_break")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("until i < items.length")
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
      muts = mutations_for("simple_while")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("loop_flip")
      end
    end
  end
end
