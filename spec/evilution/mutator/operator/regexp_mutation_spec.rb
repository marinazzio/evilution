# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RegexpMutation do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/regexp_mutation.rb", __dir__) }
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
    it "replaces simple regexp with never-matching pattern" do
      muts = mutations_for("simple_match")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('/a\A/')
      expect(muts.first.mutated_source).not_to include("/foo/")
    end

    it "preserves flags when replacing regexp" do
      muts = mutations_for("with_flags")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('/a\A/i')
    end

    it "replaces complex patterns" do
      muts = mutations_for("complex_pattern")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('/a\A/')
    end

    it "skips methods without regexps" do
      muts = mutations_for("no_regexp")

      expect(muts).to be_empty
    end

    it "mutates regexp in case/when" do
      muts = mutations_for("case_match")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('/a\A/')
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
      muts = mutations_for("simple_match")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("regexp_mutation")
      end
    end
  end
end
