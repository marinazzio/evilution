# frozen_string_literal: true

require "prism"
require "evilution/integration/loading/method_splice_evaluator"
require "evilution/mutation"
require "evilution/subject"

RSpec.describe Evilution::Integration::Loading::MethodSpliceEvaluator do
  subject(:evaluator) { described_class.new }

  def build_mutation(name:, mutated_source:, file_path: "/tmp/fake.rb", node_kind: :def)
    original = mutated_source.gsub("MUT", "OK")
    tree = Prism.parse(original).value
    node = find_node(tree, node_kind, mutation_target_for(name))
    raise "no node found for #{name}" unless node

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
      location: Evilution::Mutation::Location.new(file_path: file_path, line: node.location.start_line, column: 0)
    )
  end

  def find_node(tree, kind, predicate)
    visitor = Class.new(Prism::Visitor) do
      attr_reader :found
      def initialize(predicate, kind)
        @predicate = predicate
        @kind = kind
        @found = nil
      end

      def visit_def_node(node)
        @found ||= node if @kind == :def && @predicate.call(node)
        super
      end

      def visit_class_node(node)
        @found ||= node if @kind == :class && @predicate.call(node)
        super
      end
    end.new(predicate, kind)
    visitor.visit(tree)
    visitor.found
  end

  def mutation_target_for(name)
    method_name = name.split(/[#.]/).last
    ->(node) { node.name.to_s == method_name }
  end

  describe "#call" do
    after do
      Object.send(:remove_const, :EvilutionSpliceFoo) if defined?(::EvilutionSpliceFoo)
      Object.send(:remove_const, :EvilutionSpliceNs) if defined?(::EvilutionSpliceNs)
    end

    it "redefines an instance method on the live owner without re-executing class body" do
      class ::EvilutionSpliceFoo
        Counter = []
        Counter << :class_body_loaded
        def hello = 1
      end
      mutated = "class ::EvilutionSpliceFoo\n  Counter << :should_not_fire\n  def hello\n    2\n  end\nend\n"

      mutation = build_mutation(name: "EvilutionSpliceFoo#hello", mutated_source: mutated)

      expect(evaluator.call(mutation)).to eq(:spliced)
      expect(::EvilutionSpliceFoo.new.hello).to eq(2)
      expect(::EvilutionSpliceFoo::Counter).to eq([:class_body_loaded])
    end

    it "redefines a singleton method (def self.x) without re-executing class body" do
      class ::EvilutionSpliceFoo
        def self.hello = 1
      end
      mutated = "class ::EvilutionSpliceFoo\n  raise 'class body re-ran' if defined?(@@guard)\n  @@guard = true\n  def self.hello\n    2\n  end\nend\n"

      mutation = build_mutation(name: "EvilutionSpliceFoo.hello", mutated_source: mutated)

      expect(evaluator.call(mutation)).to eq(:spliced)
      expect(::EvilutionSpliceFoo.hello).to eq(2)
    end

    it "redefines a method inside a nested constant owner (Outer::Inner#method)" do
      module ::EvilutionSpliceNs
        class Inner
          def hello = 1
        end
      end
      mutated = "module ::EvilutionSpliceNs\n  class Inner\n    raise 'reran' if defined?(@@guard)\n    @@guard = true\n    def hello\n      2\n    end\n  end\nend\n"

      mutation = build_mutation(name: "EvilutionSpliceNs::Inner#hello", mutated_source: mutated)

      expect(evaluator.call(mutation)).to eq(:spliced)
      expect(::EvilutionSpliceNs::Inner.new.hello).to eq(2)
    end

    it "returns :not_applicable when subject.node is not a DefNode" do
      class ::EvilutionSpliceFoo; end
      mutated = "class ::EvilutionSpliceFoo\nend\n"
      mutation = build_mutation(name: "EvilutionSpliceFoo", mutated_source: mutated, node_kind: :class)

      expect(evaluator.call(mutation)).to eq(:not_applicable)
    end

    it "returns :not_applicable when owner constant is not defined" do
      mutated = "class NotDefinedAnywhere1234\n  def hello\n    2\n  end\nend\n"
      mutation = build_mutation(name: "NotDefinedAnywhere1234#hello", mutated_source: mutated)

      expect(evaluator.call(mutation)).to eq(:not_applicable)
    end

    it "returns :not_applicable when the named method is not present in mutated source" do
      class ::EvilutionSpliceFoo
        def hello = 1
      end
      mutated = "class ::EvilutionSpliceFoo\n  def world\n    2\n  end\nend\n"

      original = "class ::EvilutionSpliceFoo\n  def hello\n    1\n  end\nend\n"
      tree = Prism.parse(original).value
      node = find_node(tree, :def, ->(n) { n.name == :hello })
      subj = Evilution::Subject.new(
        name: "EvilutionSpliceFoo#hello",
        file_path: "/tmp/fake.rb",
        line_number: node.location.start_line,
        source: original,
        node: node
      )
      mutation = Evilution::Mutation.new(
        subject: subj,
        operator_name: :test_op,
        sources: Evilution::Mutation::Sources.new(original: original, mutated: mutated),
        location: Evilution::Mutation::Location.new(file_path: "/tmp/fake.rb", line: node.location.start_line, column: 0)
      )

      expect(evaluator.call(mutation)).to eq(:not_applicable)
    end
  end
end
