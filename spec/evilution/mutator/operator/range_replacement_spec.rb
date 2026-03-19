# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RangeReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/range_replacement.rb", __dir__) }
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
    it "replaces inclusive range (..) with exclusive (...)" do
      muts = mutations_for("inclusive")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a...b")
      expect(muts.first.mutated_source).not_to include("a..b")
    end

    it "replaces exclusive range (...) with inclusive (..)" do
      muts = mutations_for("exclusive")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a..b")
      expect(muts.first.mutated_source).not_to include("a...b")
    end

    it "mutates ranges inside case/when" do
      muts = mutations_for("in_case")

      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?("1...10") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("11..20") }).to be true
    end

    it "skips methods without ranges" do
      muts = mutations_for("no_range")

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
      muts = mutations_for("inclusive")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("range_replacement")
      end
    end
  end
end
