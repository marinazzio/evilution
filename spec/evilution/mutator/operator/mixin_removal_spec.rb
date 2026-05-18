# frozen_string_literal: true

require "tempfile"

require "evilution/ast/parser"
require "evilution/mutator/operator/mixin_removal"

RSpec.describe Evilution::Mutator::Operator::MixinRemoval do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/mixin_removal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  def subjects_from_source(src)
    tmpfile = Tempfile.new(["mixin_removal", ".rb"])
    tmpfile.write(src)
    tmpfile.flush
    @tmpfiles ||= []
    @tmpfiles << tmpfile
    parser.call(tmpfile.path)
  end

  after do
    Array(@tmpfiles).each do |f|
      f.close
      f.unlink
    end
  end

  let(:first_method_subject) { subjects.find { |s| s.name.include?("first_method") } }
  let(:second_method_subject) { subjects.find { |s| s.name.include?("second_method") } }
  let(:no_mixin_subject) { subjects.find { |s| s.name.include?("plain_method") } }
  let(:multiple_mixin_subject) { subjects.find { |s| s.name.include?("with_multiple") } }
  let(:module_mixin_subject) { subjects.find { |s| s.name.include?("module_method") } }

  describe "#call" do
    it "generates one mutation per mixin statement" do
      mutations = described_class.new.call(first_method_subject)

      expect(mutations.length).to eq(3)
    end

    it "only generates mutations for the first method in the class" do
      mutations = described_class.new.call(second_method_subject)

      expect(mutations).to be_empty
    end

    it "generates no mutations for a class without mixins" do
      mutations = described_class.new.call(no_mixin_subject)

      expect(mutations).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      mutations = described_class.new.call(first_method_subject)
      mutations.each do |mutation|
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(first_method_subject)

      expect(mutations.first.operator_name).to eq("mixin_removal")
    end

    it "removes the include statement" do
      mutations = described_class.new.call(first_method_subject)
      diffs = mutations.map(&:diff)

      expect(diffs).to include(a_string_including("- ", "include Comparable"))
    end

    it "removes the extend statement" do
      mutations = described_class.new.call(first_method_subject)
      diffs = mutations.map(&:diff)

      expect(diffs).to include(a_string_including("- ", "extend ClassMethods"))
    end

    it "removes the prepend statement" do
      mutations = described_class.new.call(first_method_subject)
      diffs = mutations.map(&:diff)

      expect(diffs).to include(a_string_including("- ", "prepend Logging"))
    end

    it "handles classes with multiple include statements" do
      mutations = described_class.new.call(multiple_mixin_subject)

      expect(mutations.length).to eq(2)
    end

    it "handles mixins inside modules" do
      mutations = described_class.new.call(module_mixin_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("extend ActiveSupport")
    end

    it "resets accumulated mutations between calls on the same instance" do
      src = "class C\n  include Foo\n  def m\n    1\n  end\nend\n"
      subject = subjects_from_source(src).min_by(&:line_number)
      operator = described_class.new

      first_call = operator.call(subject).length
      second_call = operator.call(subject).length

      expect(first_call).to eq(1)
      expect(second_call).to eq(1)
    end

    it "honours a filter that skips the mixin call node" do
      src = "class C\n  include Foo\n  def m\n    1\n  end\nend\n"
      subject = subjects_from_source(src).min_by(&:line_number)
      skip_all = Class.new do
        def skip?(_node) = true
      end.new

      mutations = described_class.new.call(subject, filter: skip_all)

      expect(mutations).to be_empty
    end

    it "returns no mutations for a top-level method with no enclosing scope" do
      src = "def toplevel\n  1\nend\n"
      subject = subjects_from_source(src).first

      expect { described_class.new.call(subject) }.not_to raise_error
      expect(described_class.new.call(subject)).to be_empty
    end

    it "ignores a def node named like a mixin method" do
      src = "class C\n  def include(other)\n    other\n  end\n  include Foo\n  def m\n    1\n  end\nend\n"
      subject = subjects_from_source(src).min_by(&:line_number)

      mutations = described_class.new.call(subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("include Foo")
    end

    it "ignores non-mixin bare method calls in the class body" do
      src = "class C\n  attr_reader :value\n  include Foo\n  def m\n    1\n  end\nend\n"
      subject = subjects_from_source(src).min_by(&:line_number)

      mutations = described_class.new.call(subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("include Foo")
    end

    it "finds mixins in a class nested inside another class" do
      src = "class Outer\n  class Inner\n    include Foo\n    def m\n      1\n    end\n  end\nend\n"
      subject = subjects_from_source(src).min_by(&:line_number)

      mutations = described_class.new.call(subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("include Foo")
    end

    it "finds mixins in a class nested inside a module" do
      src = "module Outer\n  class Inner\n    include Foo\n    def m\n      1\n    end\n  end\nend\n"
      subject = subjects_from_source(src).min_by(&:line_number)

      mutations = described_class.new.call(subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("include Foo")
    end
  end
end
