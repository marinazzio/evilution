# frozen_string_literal: true

require "prism"
require "evilution/integration/loading/method_splice_evaluator"
require "evilution/mutation"
require "evilution/subject"

# Test fixtures live at top level to avoid Lint/ConstantDefinitionInBlock from
# wrapping them inside RSpec.describe blocks. Re-run detection is expressed as
# `raise` in the mutated class body — if splice fails and falls back to file
# eval, the body re-runs and the example fails loudly.
module EvilutionSpliceSpec
  class Foo
    def hello = 1
  end

  class FooSingleton
    def self.hello = 1
  end

  module Ns; end

  class Ns::Inner
    def hello = 1
  end

  class EmptyOwner
    def name_with_no_separator = :marker
  end

  class DefVisitor < Prism::Visitor
    attr_reader :match

    def initialize(method_name)
      super()
      @method_name = method_name
      @match = nil
    end

    def visit_def_node(node)
      @match ||= node if node.name == @method_name
      super
    end
  end

  def self.find_def(source, method_name)
    visitor = DefVisitor.new(method_name.to_sym)
    visitor.visit(Prism.parse(source).value)
    visitor.match
  end
end

RSpec.describe Evilution::Integration::Loading::MethodSpliceEvaluator do
  subject(:evaluator) { described_class.new }

  before do
    EvilutionSpliceSpec::Foo.class_eval { def hello = 1 }
    EvilutionSpliceSpec::FooSingleton.class_eval { def self.hello = 1 }
    EvilutionSpliceSpec::Ns::Inner.class_eval { def hello = 1 }
  end

  def build_mutation(name:, mutated_source:, original_source: nil, file_path: "/tmp/fake.rb")
    original = original_source || mutated_source.gsub("    2\n", "    1\n")
    short = name.split(/[#.]/).last
    node = EvilutionSpliceSpec.find_def(original, short) || raise("no def for #{name.inspect}")

    subject_record = Evilution::Subject.new(
      name: name,
      file_path: file_path,
      line_number: node.location.start_line,
      source: original,
      node: node
    )
    Evilution::Mutation.new(
      subject: subject_record,
      operator_name: :test_op,
      sources: Evilution::Mutation::Sources.new(original: original, mutated: mutated_source),
      location: Evilution::Mutation::Location.new(
        file_path: file_path, line: node.location.start_line, column: 0
      )
    )
  end

  describe "#call" do
    it "redefines an instance method on the live owner without re-executing class body" do
      mutated = <<~RUBY
        module EvilutionSpliceSpec
          class Foo
            raise 'class body re-ran'
            def hello
              2
            end
          end
        end
      RUBY

      mutation = build_mutation(name: "EvilutionSpliceSpec::Foo#hello", mutated_source: mutated)

      expect(evaluator.call(mutation)).to eq(:spliced)
      expect(EvilutionSpliceSpec::Foo.new.hello).to eq(2)
    end

    it "redefines a singleton method (def self.x) without re-executing class body" do
      mutated = <<~RUBY
        module EvilutionSpliceSpec
          class FooSingleton
            raise 'class body re-ran'
            def self.hello
              2
            end
          end
        end
      RUBY

      mutation = build_mutation(name: "EvilutionSpliceSpec::FooSingleton.hello", mutated_source: mutated)

      expect(evaluator.call(mutation)).to eq(:spliced)
      expect(EvilutionSpliceSpec::FooSingleton.hello).to eq(2)
    end

    it "redefines a method inside a nested constant owner (Outer::Inner#method)" do
      mutated = <<~RUBY
        module EvilutionSpliceSpec
          class Ns
            class Inner
              raise 'class body re-ran'
              def hello
                2
              end
            end
          end
        end
      RUBY

      mutation = build_mutation(name: "EvilutionSpliceSpec::Ns::Inner#hello", mutated_source: mutated)

      expect(evaluator.call(mutation)).to eq(:spliced)
      expect(EvilutionSpliceSpec::Ns::Inner.new.hello).to eq(2)
    end

    it "returns :not_applicable when subject name has no method separator (# or .)" do
      original = "class EvilutionSpliceSpec::EmptyOwner\nend\n"
      subj = Evilution::Subject.new(
        name: "EvilutionSpliceSpec::EmptyOwner",
        file_path: "/tmp/fake.rb",
        line_number: 1,
        source: original,
        node: nil
      )
      mutation = Evilution::Mutation.new(
        subject: subj,
        operator_name: :test_op,
        sources: Evilution::Mutation::Sources.new(original: original, mutated: original),
        location: Evilution::Mutation::Location.new(file_path: "/tmp/fake.rb", line: 1, column: 0)
      )

      expect(evaluator.call(mutation)).to eq(:not_applicable)
    end

    it "returns :not_applicable when owner constant is not defined" do
      mutated = "class NotDefinedAnywhere1234\n  def hello\n    2\n  end\nend\n"
      mutation = build_mutation(name: "NotDefinedAnywhere1234#hello", mutated_source: mutated)

      expect(evaluator.call(mutation)).to eq(:not_applicable)
    end

    it "returns :not_applicable when the named method is not present in mutated source" do
      mutated = <<~RUBY
        module EvilutionSpliceSpec
          class Foo
            def world
              2
            end
          end
        end
      RUBY
      original = <<~RUBY
        module EvilutionSpliceSpec
          class Foo
            def hello
              1
            end
          end
        end
      RUBY
      mutation = build_mutation(
        name: "EvilutionSpliceSpec::Foo#hello",
        mutated_source: mutated,
        original_source: original
      )

      expect(evaluator.call(mutation)).to eq(:not_applicable)
    end
  end
end
