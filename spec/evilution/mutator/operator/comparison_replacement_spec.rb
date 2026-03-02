# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ComparisonReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/comparison.rb", __dir__) }
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
    it "replaces >= with > and ==" do
      muts = mutations_for("adult?")
      operators = muts.map { |m| source_diff(m) }

      expect(operators).to include(
        a_string_including("> 18"),
        a_string_including("== 18")
      )
      expect(muts.length).to eq(2)
    end

    it "replaces > with >= and ==" do
      muts = mutations_for("teenager?")
      muts.select { |m| m.mutated_source.include?("12") && !m.mutated_source.include?("> 12") }

      expect(muts.length).to eq(4)
    end

    it "replaces == with !=" do
      muts = mutations_for("equal_check")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("!=")
    end

    it "replaces != with ==" do
      muts = mutations_for("not_equal_check")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("==")
    end

    it "replaces <= with < and ==" do
      muts = mutations_for("at_most?")

      expect(muts.length).to eq(2)
      replacements = muts.map(&:mutated_source)
      expect(replacements).to include(
        a_string_including("< limit"),
        a_string_including("== limit")
      )
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
      muts = mutations_for("adult?")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("comparison_replacement")
      end
    end
  end

  def source_diff(mutation)
    mutation.mutated_source
  end
end
