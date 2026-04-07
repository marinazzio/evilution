# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RetryRemoval do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/retry_removal.rb", __dir__) }
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
    it "replaces retry with nil" do
      muts = mutations_for("simple_retry")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("nil if attempts < 3")
    end

    it "replaces unconditional retry with nil" do
      muts = mutations_for("unconditional_retry")

      expect(muts.length).to eq(1)
      expect(muts.first.diff).to include("-")
      expect(muts.first.diff).to include("retry")
    end

    it "replaces retry in method-level rescue" do
      muts = mutations_for("retry_in_method_rescue")

      expect(muts.length).to eq(1)
      expect(muts.first.diff).to include("-")
      expect(muts.first.diff).to include("retry")
    end

    it "skips methods without retry" do
      muts = mutations_for("no_retry")

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
      muts = mutations_for("unconditional_retry")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("retry_removal")
      end
    end
  end
end
