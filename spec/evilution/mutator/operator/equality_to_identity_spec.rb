# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::EqualityToIdentity do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/equality_to_identity.rb", __dir__) }
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
    it "replaces == with .equal?" do
      muts = mutations_for("simple_equality")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a.equal?(b)")
    end

    it "replaces == with literal argument" do
      muts = mutations_for("equality_with_literal")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("x.equal?(0)")
    end

    it "replaces == inside condition" do
      muts = mutations_for("equality_in_condition")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a.equal?(b)")
    end

    it "replaces == with string argument" do
      muts = mutations_for("string_equality")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('name.equal?("admin")')
    end

    it "skips != operator" do
      muts = mutations_for("not_equal")

      expect(muts).to be_empty
    end

    it "skips other comparison operators" do
      muts = mutations_for("greater_than")

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
      muts = mutations_for("simple_equality")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("equality_to_identity")
      end
    end
  end
end
