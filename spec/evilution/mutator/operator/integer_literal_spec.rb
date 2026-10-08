# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IntegerLiteral do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/integer_literal.rb", __dir__) }
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
    it "replaces 0 with 1, -1 and nil" do
      muts = mutations_for("returns_zero")

      expect(muts.length).to eq(3)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_zero\s+1\s+end/),
        a_string_matching(/def returns_zero\s+-1\s+end/),
        a_string_matching(/def returns_zero\s+nil\s+end/)
      )
    end

    it "replaces 1 with 0 and nil" do
      muts = mutations_for("returns_one")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_one\s+0\s+end/),
        a_string_matching(/def returns_one\s+nil\s+end/)
      )
    end

    it "replaces 42 with 0, 43, 41 and nil" do
      muts = mutations_for("returns_forty_two")

      expect(muts.length).to eq(4)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_forty_two\s+0\s+end/),
        a_string_matching(/def returns_forty_two\s+43\s+end/),
        a_string_matching(/def returns_forty_two\s+41\s+end/),
        a_string_matching(/def returns_forty_two\s+nil\s+end/)
      )
    end

    it "lowers a negative literal" do
      mutated_sources = mutations_for("returns_minus_five").map(&:mutated_source)

      expect(mutated_sources).to include(a_string_matching(/def returns_minus_five\s+-6\s+end/))
    end

    it "keeps a subtraction written without spaces valid" do
      mutation = mutations_for("subtracts_zero").find { |m| m.mutated_source.include?("count--1") }

      expect(Prism.parse(mutation.mutated_source).success?).to be(true)
    end

    it "keeps an argument written without parentheses an argument" do
      mutation = mutations_for("passes_zero").find { |m| m.mutated_source.include?("record -1") }
      call = Prism.parse(mutation.mutated_source).value.statements.body.first.body.body.last.body.body.first

      expect(call.name).to eq(:record)
      expect(call.arguments.arguments.map(&:slice)).to eq(["-1"])
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
      muts = mutations_for("returns_zero")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("integer_literal")
      end
    end
  end
end
