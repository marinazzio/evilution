# frozen_string_literal: true

# rubocop:disable Lint/InterpolationCheck
RSpec.describe Evilution::Mutator::Operator::StringInterpolation do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/string_interpolation.rb", __dir__) }
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
    it "replaces interpolation content with nil" do
      muts = mutations_for("simple_interpolation")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('#{nil}')
    end

    it "generates one mutation per interpolation" do
      muts = mutations_for("multiple_interpolations")

      expect(muts.length).to eq(2)
      sources = muts.map(&:mutated_source)
      expect(sources).to include(a_string_including('#{nil} #{last}'))
      expect(sources).to include(a_string_including('#{first} #{nil}'))
    end

    it "replaces method call interpolation content" do
      muts = mutations_for("method_call_interpolation")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('#{nil}')
    end

    it "replaces expression interpolation content" do
      muts = mutations_for("expression_interpolation")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('#{nil}')
    end

    it "handles interpolation with surrounding text" do
      muts = mutations_for("interpolation_with_surrounding_text")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('"Dear #{nil}, welcome!"')
    end

    it "handles symbol interpolation" do
      muts = mutations_for("symbol_interpolation")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('#{nil}')
    end

    it "skips plain strings without interpolation" do
      muts = mutations_for("no_interpolation")

      expect(muts).to be_empty
    end

    it "skips empty interpolation" do
      muts = mutations_for("empty_interpolation")

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
      muts = mutations_for("simple_interpolation")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("string_interpolation")
      end
    end
  end
end
# rubocop:enable Lint/InterpolationCheck
