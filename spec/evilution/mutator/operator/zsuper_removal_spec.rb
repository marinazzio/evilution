# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ZsuperRemoval do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/zsuper.rb", __dir__) }
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
    it "removes implicit super call" do
      muts = mutations_for("greet")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("nil")
      expect(muts.first.mutated_source).not_to match(/def greet.*\n\s+super/)
    end

    it "removes implicit super with forwarded arguments" do
      muts = mutations_for("work")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("nil")
      expect(muts.first.mutated_source).not_to match(/def work.*\n\s+super/)
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          expect { Prism.parse(mutation.mutated_source) }.not_to raise_error,
                                                                 "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("greet")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("zsuper_removal")
      end
    end

    it "does not mutate methods without super" do
      muts = mutations_for("no_super")

      expect(muts).to be_empty
    end
  end
end
