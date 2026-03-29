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

    it "generates suggestions for all #{Evilution::Reporter::Suggestion::TEMPLATES.size} operator types" do
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

    describe "array_literal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("array_literal", diff: "-   items = [1, 2, 3]\n+   items = []")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated values" do
        mutation = build_mutation("array_literal", diff: "-   items = [1, 2, 3]\n+   items = []")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("[1, 2, 3]")
        expect(suggestion).to include("[]")
      end

      it "advises asserting contents or size" do
        mutation = build_mutation("array_literal", diff: "-   items = [1, 2, 3]\n+   items = nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("contents").or include("size").or include("elements")
      end
    end

    describe "hash_literal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("hash_literal", diff: "-   opts = { a: 1 }\n+   opts = {}")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated values" do
        mutation = build_mutation("hash_literal", diff: "-   opts = { a: 1 }\n+   opts = {}")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("{ a: 1 }")
        expect(suggestion).to include("{}")
      end

      it "advises asserting keys and values" do
        mutation = build_mutation("hash_literal", diff: "-   opts = { a: 1 }\n+   opts = nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("keys").or include("values").or include("contents")
      end
    end

    describe "collection_replacement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("collection_replacement", diff: "-   items.map { |x| x * 2 }\n+   items.each { |x| x * 2 }")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated calls" do
        mutation = build_mutation("collection_replacement", diff: "-   items.map { |x| x * 2 }\n+   items.each { |x| x * 2 }")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("map")
        expect(suggestion).to include("each")
      end

      it "advises asserting return value" do
        mutation = build_mutation("collection_replacement", diff: "-   items.select { |x| x > 0 }\n+   items.reject { |x| x > 0 }")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("return")
      end
    end

    describe "conditional_negation" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("conditional_negation", diff: "-   if active?\n+   if !active?")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated conditions" do
        mutation = build_mutation("conditional_negation", diff: "-   if active?\n+   if !active?")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("active?")
        expect(suggestion).to include("!active?")
      end

      it "advises exercising both branches" do
        mutation = build_mutation("conditional_negation", diff: "-   if valid?\n+   if !valid?")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("both").or include("branch")
      end
    end

    describe "conditional_branch" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("conditional_branch", diff: "-   if x > 0 then y else z end\n+   if x > 0 then y else nil end")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated branches" do
        mutation = build_mutation("conditional_branch", diff: "-   if x > 0 then y else z end\n+   if x > 0 then y else nil end")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("z end")
        expect(suggestion).to include("nil end")
      end

      it "advises exercising the removed branch" do
        mutation = build_mutation("conditional_branch", diff: "-   if flag\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("branch")
      end
    end

    describe "statement_deletion" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("statement_deletion", diff: "-   @count += 1\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the deleted statement" do
        mutation = build_mutation("statement_deletion", diff: "-   @count += 1\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("@count += 1")
      end

      it "advises testing side effects" do
        mutation = build_mutation("statement_deletion", diff: "-   save!\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("side effect").or include("depend")
      end
    end

    describe "method_body_replacement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("method_body_replacement", diff: "-   calculate(x)\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "advises asserting return value or side effects" do
        mutation = build_mutation("method_body_replacement", diff: "-   calculate(x)\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("return").or include("side effect")
      end
    end

    describe "return_value_removal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("return_value_removal", diff: "-   return result\n+   result")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "advises asserting the return value" do
        mutation = build_mutation("return_value_removal", diff: "-   return result\n+   result")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("return value")
      end
    end

    describe "method_call_removal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("method_call_removal", diff: "-   obj.save\n+   obj")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the removed call" do
        mutation = build_mutation("method_call_removal", diff: "-   obj.save\n+   obj")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("obj.save")
      end

      it "advises asserting return value or side effect" do
        mutation = build_mutation("method_call_removal", diff: "-   list.sort\n+   list")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("return").or include("side effect")
      end
    end

    describe "nil_replacement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("nil_replacement", diff: "-   return nil\n+   return true")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated values" do
        mutation = build_mutation("nil_replacement", diff: "-   return nil\n+   return 0")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("nil")
        expect(suggestion).to include("0")
      end

      it "advises asserting non-nil return value" do
        mutation = build_mutation("nil_replacement", diff: "-   return nil\n+   return false")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("nil")
      end
    end

    describe "compound_assignment" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("compound_assignment", diff: "-   x += 1\n+   x -= 1")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated operators" do
        mutation = build_mutation("compound_assignment", diff: "-   x += 1\n+   x -= 1")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("+=")
        expect(suggestion).to include("-=")
      end

      it "handles removal mutation" do
        mutation = build_mutation("compound_assignment", diff: "-   @count += 1\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("side effect").or include("assignment")
      end

      it "handles logical compound assignment" do
        mutation = build_mutation("compound_assignment", diff: "-   x &&= true\n+   x ||= true")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("&&=")
        expect(suggestion).to include("||=")
      end
    end

    describe "superclass_removal" do
      it "generates an RSpec it-block referencing the superclass" do
        mutation = build_mutation("superclass_removal",
                                  diff: "-   class Admin < User\n+   class Admin")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the removed superclass in a comment" do
        mutation = build_mutation("superclass_removal",
                                  diff: "-   class Admin < User\n+   class Admin")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("User")
      end

      it "advises testing inherited behavior" do
        mutation = build_mutation("superclass_removal",
                                  diff: "-   class Admin < User\n+   class Admin")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("inherit")
      end
    end

    describe "local_variable_assignment" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("local_variable_assignment",
                                  diff: "-   result = compute(x)\n+   compute(x)")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the removed assignment in a comment" do
        mutation = build_mutation("local_variable_assignment",
                                  diff: "-   result = compute(x)\n+   compute(x)")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("result = compute(x)")
        expect(suggestion).to include("compute(x)")
      end

      it "advises testing that the variable is used after assignment" do
        mutation = build_mutation("local_variable_assignment",
                                  diff: "-   total = a + b\n+   a + b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("variable").or include("assigned")
      end
    end

    describe "instance_variable_write" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("instance_variable_write",
                                  diff: "-   @name = value\n+   value")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the removed assignment in a comment" do
        mutation = build_mutation("instance_variable_write",
                                  diff: "-   @name = value\n+   value")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("@name = value")
      end

      it "handles nil replacement mutation" do
        mutation = build_mutation("instance_variable_write",
                                  diff: "-   @name = value\n+   @name = nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("nil")
      end

      it "advises testing the instance variable state" do
        mutation = build_mutation("instance_variable_write",
                                  diff: "-   @count = 0\n+   0")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("instance variable").or include("@")
      end
    end

    describe "class_variable_write" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("class_variable_write",
                                  diff: "-   @@count = 0\n+   0")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the removed assignment in a comment" do
        mutation = build_mutation("class_variable_write",
                                  diff: "-   @@count = 0\n+   0")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("@@count = 0")
      end

      it "handles nil replacement mutation" do
        mutation = build_mutation("class_variable_write",
                                  diff: "-   @@count = 0\n+   @@count = nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("nil")
      end

      it "advises testing the class variable state" do
        mutation = build_mutation("class_variable_write",
                                  diff: "-   @@count = 0\n+   0")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("class variable").or include("@@").or include("shared")
      end
    end

    describe "global_variable_write" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("global_variable_write",
                                  diff: "-   $output = compute\n+   compute")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the removed assignment in a comment" do
        mutation = build_mutation("global_variable_write",
                                  diff: "-   $output = compute\n+   compute")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("$output = compute")
      end

      it "handles nil replacement mutation" do
        mutation = build_mutation("global_variable_write",
                                  diff: "-   $output = compute\n+   $output = nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("nil")
      end

      it "advises testing the global variable state" do
        mutation = build_mutation("global_variable_write",
                                  diff: "-   $verbose = true\n+   true")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("global variable").or include("$")
      end
    end

    describe "mixin_removal" do
      it "generates an RSpec it-block referencing the mixin" do
        mutation = build_mutation("mixin_removal",
                                  diff: "-   include Comparable\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the removed mixin in a comment" do
        mutation = build_mutation("mixin_removal",
                                  diff: "-   include Comparable\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("Comparable")
      end

      it "advises testing mixin-provided behavior" do
        mutation = build_mutation("mixin_removal",
                                  diff: "-   extend ClassMethods\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("mixin").or include("module").or include("include")
      end
    end

    describe "rescue_removal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("rescue_removal",
                                  diff: "-   rescue ArgumentError\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the removed rescue clause in a comment" do
        mutation = build_mutation("rescue_removal",
                                  diff: "-   rescue ArgumentError\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("rescue ArgumentError")
      end

      it "advises testing exception handling" do
        mutation = build_mutation("rescue_removal",
                                  diff: "-   rescue StandardError => e\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("rescue").or include("exception").or include("handler")
      end
    end

    describe "rescue_body_replacement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("rescue_body_replacement",
                                  diff: "-   log(e)\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated values in a comment" do
        mutation = build_mutation("rescue_body_replacement",
                                  diff: "-   log(e)\n+   raise")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("log(e)")
        expect(suggestion).to include("raise")
      end

      it "advises triggering the exception" do
        mutation = build_mutation("rescue_body_replacement",
                                  diff: "-   fallback_value\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("rescue").or include("exception").or include("raises")
      end
    end

    describe "inline_rescue" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("inline_rescue",
                                  diff: "-   dangerous_call rescue fallback\n+   dangerous_call")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated values in a comment" do
        mutation = build_mutation("inline_rescue",
                                  diff: "-   dangerous_call rescue fallback\n+   dangerous_call rescue nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("fallback")
        expect(suggestion).to include("nil")
      end

      it "advises testing the fallback value" do
        mutation = build_mutation("inline_rescue",
                                  diff: "-   dangerous_call rescue fallback\n+   dangerous_call")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("rescue").or include("fallback").or include("exception")
      end
    end

    describe "ensure_removal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("ensure_removal",
                                  diff: "-   ensure\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the removed ensure in a comment" do
        mutation = build_mutation("ensure_removal",
                                  diff: "-   ensure\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("ensure")
      end

      it "advises testing cleanup side effects" do
        mutation = build_mutation("ensure_removal",
                                  diff: "-   cleanup\n+   ")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("cleanup").or include("ensure").or include("side effect")
      end
    end

    describe "break_statement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("break_statement",
                                  diff: "-   break item.value\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated values in a comment" do
        mutation = build_mutation("break_statement",
                                  diff: "-   break item.value\n+   next item.value")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("break item.value")
        expect(suggestion).to include("next item.value")
      end

      it "advises testing loop exit behavior" do
        mutation = build_mutation("break_statement",
                                  diff: "-   break\n+   next")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("break").or include("loop").or include("exit")
      end
    end

    describe "next_statement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("next_statement",
                                  diff: "-   next item.default\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated values in a comment" do
        mutation = build_mutation("next_statement",
                                  diff: "-   next item.default\n+   break item.default")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("next item.default")
        expect(suggestion).to include("break item.default")
      end

      it "advises testing iteration skip behavior" do
        mutation = build_mutation("next_statement",
                                  diff: "-   next\n+   break")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("next").or include("iteration").or include("skip")
      end
    end

    describe "redo_statement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("redo_statement",
                                  diff: "-   redo\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the removed redo in a comment" do
        mutation = build_mutation("redo_statement",
                                  diff: "-   redo\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("redo")
      end

      it "advises testing retry logic" do
        mutation = build_mutation("redo_statement",
                                  diff: "-   redo\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("redo").or include("retry").or include("restart")
      end
    end

    describe "bang_method" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("bang_method",
                                  diff: "-   items.sort!\n+   items.sort")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated methods in a comment" do
        mutation = build_mutation("bang_method",
                                  diff: "-   items.sort!\n+   items.sort")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("sort!")
        expect(suggestion).to include("sort")
      end

      it "advises testing in-place vs copy semantics" do
        mutation = build_mutation("bang_method",
                                  diff: "-   items.map!\n+   items.map")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("in-place").or include("copy").or include("modified")
      end
    end

    describe "bitwise_replacement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("bitwise_replacement",
                                  diff: "-   a & b\n+   a | b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated operators in a comment" do
        mutation = build_mutation("bitwise_replacement",
                                  diff: "-   a & b\n+   a | b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("&")
        expect(suggestion).to include("|")
      end

      it "advises testing bitwise result precision" do
        mutation = build_mutation("bitwise_replacement",
                                  diff: "-   a ^ b\n+   a & b")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("bitwise").or include("bit-level")
      end
    end

    describe "bitwise_complement" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("bitwise_complement",
                                  diff: "-   ~a\n+   a")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated code in a comment" do
        mutation = build_mutation("bitwise_complement",
                                  diff: "-   ~a\n+   -a")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("~")
      end

      it "advises testing complement behavior" do
        mutation = build_mutation("bitwise_complement",
                                  diff: "-   ~a\n+   a")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("complement").or include("bitwise")
      end
    end

    describe "zsuper_removal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("zsuper_removal",
                                  diff: "-   super\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated code in a comment" do
        mutation = build_mutation("zsuper_removal",
                                  diff: "-   super\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("super")
        expect(suggestion).to include("nil")
      end

      it "advises testing inherited behavior" do
        mutation = build_mutation("zsuper_removal",
                                  diff: "-   super\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("inherited").or include("super")
      end
    end

    describe "explicit_super_mutation" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("explicit_super_mutation",
                                  diff: "-   super(a, b)\n+   super")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated code in a comment" do
        mutation = build_mutation("explicit_super_mutation",
                                  diff: "-   super(a, b)\n+   super(a)")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("super(a, b)")
        expect(suggestion).to include("super(a)")
      end

      it "advises testing super arguments matter" do
        mutation = build_mutation("explicit_super_mutation",
                                  diff: "-   super(a, b)\n+   super()")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("argument").or include("super")
      end
    end

    describe "index_to_fetch" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("index_to_fetch",
                                  diff: "-   h[:key]\n+   h.fetch(:key)")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated code in a comment" do
        mutation = build_mutation("index_to_fetch",
                                  diff: "-   h[:key]\n+   h.fetch(:key)")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("h[:key]")
        expect(suggestion).to include("h.fetch(:key)")
      end

      it "advises testing missing key behavior" do
        mutation = build_mutation("index_to_fetch",
                                  diff: "-   h[:key]\n+   h.fetch(:key)")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("KeyError").or include("fetch").or include("missing")
      end
    end

    describe "index_to_dig" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("index_to_dig",
                                  diff: "-   h[:a][:b]\n+   h.dig(:a, :b)")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated code in a comment" do
        mutation = build_mutation("index_to_dig",
                                  diff: "-   h[:a][:b]\n+   h.dig(:a, :b)")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("h[:a][:b]")
        expect(suggestion).to include("h.dig(:a, :b)")
      end

      it "advises testing nested access" do
        mutation = build_mutation("index_to_dig",
                                  diff: "-   h[:a][:b]\n+   h.dig(:a, :b)")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("nested").or include("chained").or include("dig")
      end
    end

    describe "index_assignment_removal" do
      it "generates an RSpec it-block with the method name" do
        mutation = build_mutation("index_assignment_removal",
                                  diff: "-   h[:key] = val\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("it")
        expect(suggestion).to include("expect")
        expect(suggestion).to include("bar")
      end

      it "references the original and mutated code in a comment" do
        mutation = build_mutation("index_assignment_removal",
                                  diff: "-   h[:key] = val\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("h[:key] = val")
        expect(suggestion).to include("nil")
      end

      it "advises testing collection modification" do
        mutation = build_mutation("index_assignment_removal",
                                  diff: "-   h[:key] = val\n+   nil")

        suggestion = suggestion_reporter.suggestion_for(mutation)

        expect(suggestion).to include("collection").or include("[]=").or include("modif")
      end
    end

    it "falls back to static template for operators without concrete suggestions" do
      mutation = build_mutation("argument_removal")

      suggestion = suggestion_reporter.suggestion_for(mutation)

      expect(suggestion).to include("correct arguments")
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
