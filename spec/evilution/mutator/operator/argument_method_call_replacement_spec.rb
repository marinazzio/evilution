# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/argument_method_call_replacement"

RSpec.describe Evilution::Mutator::Operator::ArgumentMethodCallReplacement do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/argument_method_call_replacement.rb", __dir__)
  end
  let(:subjects) { parser.call(fixture_path) }

  def subject_named(name)
    subjects.find { |s| s.name.include?(name) }
  end

  def diffs_for(method_name)
    described_class.new.call(subject_named(method_name)).map(&:diff)
  end

  describe "#call" do
    it "drops a method call from a positional argument (fn(x.attr) -> fn(x))" do
      expect(diffs_for("call_arg")).to include(match(/-\s*log\(parsed\.from_id\).*\+\s*log\(parsed\)/m))
    end

    it "drops a method call inside a hash value" do
      expect(diffs_for("hash_value"))
        .to include(match(/-\s*log\(\{ from_id: parsed\.from_id \}\.to_json\).*\+\s*log\(\{ from_id: parsed \}\.to_json\)/m))
    end

    it "drops a method call inside an array element" do
      expect(diffs_for("array_element")).to include(match(/parsed\.from_id, other\.name/))
      expect(diffs_for("array_element")).to include(match(/parsed, other\.name/))
    end

    it "drops the trailing method on a chained call (a.b.c -> a.b)" do
      expect(diffs_for("chained_call")).to include(match(/-\s*log\(a\.b\.c\).*\+\s*log\(a\.b\)/m))
    end

    it "drops a method call with a block argument" do
      expect(diffs_for("call_with_block")).to include(match(/-\s*log\(parsed\.attrs \{ \|x\| x \}\).*\+\s*log\(parsed\)/m))
    end

    it "drops a method call from a keyword argument value" do
      expect(diffs_for("nested_in_kwarg")).to include(match(/-\s*log\(payload: parsed\.from_id\).*\+\s*log\(payload: parsed\)/m))
    end

    it "does not fire on arguments that are not method calls" do
      expect(diffs_for("no_receiver_arg")).to be_empty
    end

    it "does not fire on calls with no arguments" do
      expect(diffs_for("no_args_call")).to be_empty
    end

    it "produces parseable Ruby for every mutation" do
      subjects.each do |s|
        described_class.new.call(s).each do |mutation|
          parse = Prism.parse(mutation.mutated_source)
          expect(parse.errors).to be_empty,
                                  "invalid Ruby: #{mutation.mutated_source.inspect}; errors: #{parse.errors.map(&:message).join(", ")}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(subject_named("call_arg"))

      expect(mutations.first.operator_name).to eq("argument_method_call_replacement")
    end
  end
end
