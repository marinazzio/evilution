# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ScalarReturn do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/scalar_return.rb", __dir__) }
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
    it "skips single-expression bodies to avoid overlap with literal operators" do
      expect(mutations_for("returns_string")).to be_empty
      expect(mutations_for("returns_integer")).to be_empty
      expect(mutations_for("returns_float")).to be_empty
    end

    it "replaces entire body with empty string when last expression is a non-empty string" do
      muts = mutations_for("multi_line_returns_string")

      expect(muts.length).to eq(1)
      method_body = muts.first.mutated_source[/def multi_line_returns_string\n(.+?)\n  end/m, 1]
      expect(method_body.strip).to eq('""')
    end

    it "replaces entire body with 0 when last expression is a non-zero integer" do
      muts = mutations_for("multi_line_returns_integer")

      expect(muts.length).to eq(1)
      method_body = muts.first.mutated_source[/def multi_line_returns_integer\n(.+?)\n  end/m, 1]
      expect(method_body.strip).to eq("0")
    end

    it "replaces entire body with 0.0 when last expression is a non-zero float" do
      muts = mutations_for("multi_line_returns_float")

      expect(muts.length).to eq(1)
      method_body = muts.first.mutated_source[/def multi_line_returns_float\n(.+?)\n  end/m, 1]
      expect(method_body.strip).to eq("0.0")
    end

    it "does not mutate when last expression is already the zero value" do
      expect(mutations_for("multi_line_returns_zero")).to be_empty
      expect(mutations_for("multi_line_returns_empty_string")).to be_empty
      expect(mutations_for("multi_line_returns_zero_float")).to be_empty
    end

    it "does not mutate non-scalar returns" do
      expect(mutations_for("returns_array")).to be_empty
      expect(mutations_for("returns_nil")).to be_empty
    end

    it "does not mutate empty methods" do
      expect(mutations_for("empty_method")).to be_empty
    end

    it "recurses into a method body to mutate a nested def" do
      # The outer def's last expression is the nested def (non-scalar, so the
      # outer yields nothing); the nested def's multi-line scalar body is only
      # mutated when the visitor recurses into the outer def's body.
      muts = mutations_for("outer_with_nested_def")

      expect(muts.length).to eq(1)
      method_body = muts.first.mutated_source[/def inner_method\n(.+?)\n    end/m, 1]
      expect(method_body.strip).to eq('""')
    end

    it "handles a method whose body is a begin/rescue rather than statements" do
      # `rescue_body_method`'s body is a BeginNode, not a StatementsNode. The
      # operator must guard with an explicit type check before reading
      # `body.body` — a truthiness-only check would raise NoMethodError.
      expect { mutations_for("rescue_body_method") }.not_to raise_error
      expect(mutations_for("rescue_body_method")).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("multi_line_returns_string")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("scalar_return")
      end
    end
  end
end
