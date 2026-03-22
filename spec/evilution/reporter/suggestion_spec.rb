# frozen_string_literal: true

require "evilution/reporter/suggestion"

RSpec.describe Evilution::Reporter::Suggestion do
  subject(:suggestion_reporter) { described_class.new }

  let(:subject_obj) do
    double("Subject", name: "Foo#bar", file_path: "lib/foo.rb")
  end

  def build_mutation(operator_name, diff: "- a >= b\n+ a > b", subject: nil)
    double(
      "Mutation",
      operator_name: operator_name,
      file_path: "lib/foo.rb",
      line: 5,
      diff: diff,
      subject: subject || subject_obj
    )
  end

  def build_result(mutation, status: :survived)
    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: status,
      duration: 0.1
    )
  end

  describe "#call" do
    it "returns suggestions for survived mutations" do
      mutation = build_mutation("comparison_replacement")
      survived = build_result(mutation)
      summary = Evilution::Result::Summary.new(results: [survived])

      result = suggestion_reporter.call(summary)

      expect(result.size).to eq(1)
      expect(result.first[:mutation]).to eq(mutation)
      expect(result.first[:suggestion]).to include("boundary condition")
    end

    it "skips killed mutations" do
      mutation = build_mutation("comparison_replacement")
      killed = build_result(mutation, status: :killed)
      summary = Evilution::Result::Summary.new(results: [killed])

      result = suggestion_reporter.call(summary)

      expect(result).to be_empty
    end

    it "generates suggestions for all 18 operator types" do
      Evilution::Reporter::Suggestion::TEMPLATES.each_key do |operator_name|
        mutation = build_mutation(operator_name)
        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to be_a(String)
        expect(suggestion.length).to be > 10
      end
    end

    it "returns a default suggestion for unknown operators" do
      mutation = build_mutation("unknown_operator")

      suggestion = suggestion_reporter.suggestion_for(mutation)

      expect(suggestion).to eq(Evilution::Reporter::Suggestion::DEFAULT_SUGGESTION)
    end

    it "handles multiple survived mutations" do
      m1 = build_mutation("comparison_replacement")
      m2 = build_mutation("boolean_operator_replacement")
      results = [build_result(m1), build_result(m2)]
      summary = Evilution::Result::Summary.new(results: results)

      suggestions = suggestion_reporter.call(summary)

      expect(suggestions.size).to eq(2)
      expect(suggestions.map { |s| s[:suggestion] }.uniq.size).to eq(2)
    end

    it "handles an empty summary" do
      summary = Evilution::Result::Summary.new(results: [])

      result = suggestion_reporter.call(summary)

      expect(result).to eq([])
    end
  end

  describe "concrete suggestions (suggest_tests: true)" do
    subject(:suggestion_reporter) { described_class.new(suggest_tests: true) }

    describe "comparison_replacement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("comparison_replacement", diff: "-   if a > b\n+   if a >= b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated operators in a comment" do
        mutation = build_mutation("comparison_replacement", diff: "-   if a > b\n+   if a >= b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include(">")
        expect(suggestion).to include(">=")
      end

      it "includes boundary condition guidance" do
        mutation = build_mutation("comparison_replacement", diff: "-   x == y\n+   x != y")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
      end

      it "handles namespaced class with instance method" do
        subj = double("Subject", name: "Foo::Bar#baz", file_path: "lib/foo/bar.rb")
        mutation = build_mutation("comparison_replacement", diff: "-   a < b\n+   a <= b", subject: subj)

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("baz")
      end

      it "handles class method syntax" do
        subj = double("Subject", name: "Foo.bar", file_path: "lib/foo.rb")
        mutation = build_mutation("comparison_replacement", diff: "-   a < b\n+   a <= b", subject: subj)

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("bar")
      end
    end

    describe "arithmetic_replacement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("arithmetic_replacement", diff: "-   a + b\n+   a - b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated operators" do
        mutation = build_mutation("arithmetic_replacement", diff: "-   total = x * y\n+   total = x / y")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("*")
        expect(suggestion).to include("/")
      end

      it "includes arithmetic verification guidance" do
        mutation = build_mutation("arithmetic_replacement", diff: "-   a + b\n+   a - b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
      end
    end

    describe "boolean_operator_replacement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("boolean_operator_replacement", diff: "-   a && b\n+   a || b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated operators" do
        mutation = build_mutation("boolean_operator_replacement", diff: "-   a && b\n+   a || b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("&&")
        expect(suggestion).to include("||")
      end

      it "advises testing with one condition true and one false" do
        mutation = build_mutation("boolean_operator_replacement", diff: "-   a && b\n+   a || b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("one")
        expect(suggestion).to include("true")
      end
    end

    describe "boolean_literal_replacement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("boolean_literal_replacement", diff: "-   return true\n+   return false")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated values" do
        mutation = build_mutation("boolean_literal_replacement", diff: "-   return true\n+   return false")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("true")
        expect(suggestion).to include("false")
      end

      it "handles true-to-nil mutation" do
        mutation = build_mutation("boolean_literal_replacement", diff: "-   return true\n+   return nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
      end
    end

    describe "negation_insertion" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("negation_insertion", diff: "-   foo.valid?\n+   !foo.valid?")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "advises asserting the exact boolean result" do
        mutation = build_mutation("negation_insertion", diff: "-   foo.valid?\n+   !foo.valid?")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("true").or include("false").or include("eq")
      end
    end

    describe "integer_literal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("integer_literal", diff: "-   count = 0\n+   count = 1")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated values" do
        mutation = build_mutation("integer_literal", diff: "-   count = 0\n+   count = 1")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("0")
        expect(suggestion).to include("1")
      end

      it "advises asserting exact numeric value" do
        mutation = build_mutation("integer_literal", diff: "-   limit = 5\n+   limit = 0")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("exact")
      end
    end

    describe "float_literal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("float_literal", diff: "-   rate = 0.5\n+   rate = 0.0")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated values" do
        mutation = build_mutation("float_literal", diff: "-   rate = 0.5\n+   rate = 0.0")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("0.5")
        expect(suggestion).to include("0.0")
      end
    end

    describe "string_literal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("string_literal", diff: "-   name = \"hello\"\n+   name = \"\"")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "advises asserting exact string content" do
        mutation = build_mutation("string_literal", diff: "-   name = \"hello\"\n+   name = \"\"")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("exact")
      end
    end

    describe "symbol_literal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("symbol_literal", diff: "-   status = :active\n+   status = :\"evilution_mutated\"")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "advises asserting exact symbol value" do
        mutation = build_mutation("symbol_literal", diff: "-   status = :active\n+   status = :\"evilution_mutated\"")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("exact")
      end
    end

    it "falls back to static template for operators without concrete suggestions" do
      mutation = build_mutation("statement_deletion")

      suggestion = suggestion_reporter.suggestion_for(mutation)

      expect(suggestion).to include("side effect")
    end

    it "returns default suggestion for unknown operators" do
      mutation = build_mutation("unknown_operator")

      suggestion = suggestion_reporter.suggestion_for(mutation)

      expect(suggestion).to eq(described_class::DEFAULT_SUGGESTION)
    end
  end

  describe "suggest_tests: false (default)" do
    it "returns static template even for operators with concrete suggestions" do
      mutation = build_mutation("comparison_replacement", diff: "-   a > b\n+   a >= b")

      suggestion = suggestion_reporter.suggestion_for(mutation)

      expect(suggestion).to eq("Add a test for the boundary condition where the comparison operand equals the threshold exactly")
    end
  end
end
