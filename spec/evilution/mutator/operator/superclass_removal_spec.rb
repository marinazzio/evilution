# frozen_string_literal: true

require "tempfile"

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

    def diffs_for(src, method_name)
      tmpfile = Tempfile.new(["superclass_removal", ".rb"])
      tmpfile.write(src)
      tmpfile.flush
      subject = parser.call(tmpfile.path).find { |s| s.name.end_with?("##{method_name}", ".#{method_name}") }
      described_class.new.call(subject).map(&:diff)
    ensure
      tmpfile.close
      tmpfile.unlink
    end

    it "anchors on a first method written in a block of the body" do
      src = "class Sized < Base\n  configure do\n    def size = 1\n  end\nend\n"

      expect(diffs_for(src, "size")).to contain_exactly(a_string_including("- class Sized < Base", "+ class Sized"))
    end

    it "reaches a class whose only methods sit in a singleton class" do
      src = "class Report < Base\n  class << self\n    def build = new\n    def other = 1\n  end\nend\n"

      expect(diffs_for(src, "build")).to contain_exactly(a_string_including("- class Report < Base", "+ class Report"))
      expect(diffs_for(src, "other")).to be_empty
    end

    it "leaves the class alone for a singleton class's method when the class has a method of its own" do
      src = "class Report < Base\n  class << self\n    def build = new\n  end\n  def to_s = 1\nend\n"

      expect(diffs_for(src, "build")).to be_empty
      expect(diffs_for(src, "to_s").length).to eq(1)
    end

    it "leaves a module alone" do
      expect(diffs_for("module M\n  def a = 1\nend\n", "a")).to be_empty
    end
  end
end
