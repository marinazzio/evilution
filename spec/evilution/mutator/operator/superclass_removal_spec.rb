# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/superclass_removal"

RSpec.describe Evilution::Mutator::Operator::SuperclassRemoval do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/superclass_removal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:admin_first) { subjects.find { |s| s.name.include?("admin?") } }
  let(:admin_second) { subjects.find { |s| s.name.include?("role") } }
  let(:no_parent_subject) { subjects.find { |s| s.name.include?("no_parent") } }
  let(:namespaced_superclass_subject) { subjects.find { |s| s.name.include?("save") } }
  let(:non_def_first_subject) { subjects.find { |s| s.name.include?("lookup") } }
  let(:nested_class_subject) { subjects.find { |s| s.name.include?("inner_method") } }

  describe "#call" do
    it "generates one mutation for a class with a superclass" do
      mutations = described_class.new.call(admin_first)

      expect(mutations.length).to eq(1)
    end

    it "only generates mutations for the first method in the class" do
      mutations = described_class.new.call(admin_second)

      expect(mutations).to be_empty
    end

    it "generates no mutations for a class without a superclass" do
      mutations = described_class.new.call(no_parent_subject)

      expect(mutations).to be_empty
    end

    it "produces valid Ruby" do
      mutations = described_class.new.call(admin_first)
      mutations.each do |mutation|
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(admin_first)

      expect(mutations.first.operator_name).to eq("superclass_removal")
    end

    it "removes the superclass from the class definition" do
      mutations = described_class.new.call(admin_first)

      expect(mutations.first.diff).to include("- class Admin < User")
      expect(mutations.first.diff).to include("+ class Admin")
    end

    it "handles namespaced superclasses" do
      mutations = described_class.new.call(namespaced_superclass_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("- class Service < ActiveRecord::Base")
      expect(mutations.first.diff).to include("+ class Service")
    end

    it "removes only the superclass, keeping the class name intact" do
      mutations = described_class.new.call(admin_first)

      expect(mutations.first.mutated_source.lines.first).to eq("class Admin\n")
    end

    it "anchors on the first def even when a non-def statement precedes it" do
      mutations = described_class.new.call(non_def_first_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("- class WithConstant < User")
      expect(mutations.first.diff).to include("+ class WithConstant")
    end

    it "finds the innermost enclosing class for a nested class definition" do
      mutations = described_class.new.call(nested_class_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("-   class Inner < User")
      expect(mutations.first.diff).to include("+   class Inner")
    end

    it "returns an empty list and ignores stale state across successive calls" do
      operator = described_class.new
      first = operator.call(admin_first)
      second = operator.call(no_parent_subject)

      expect(first.length).to eq(1)
      expect(second).to eq([])
    end

    it "returns the mutations array, not nil" do
      operator = described_class.new

      expect(operator.call(admin_first)).to be_an(Array)
    end

    it "honors a filter that skips the class node" do
      filter = Evilution::AST::Pattern::Filter.new(["class"])

      mutations = described_class.new.call(admin_first, filter: filter)

      expect(mutations).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
