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

    def diffs_for(src, method_name)
      subject = subjects_from_source(src).find { |s| s.name.end_with?("##{method_name}", ".#{method_name}") }
      described_class.new.call(subject).map(&:diff)
    end

    it "anchors on a first method written in a block of the body" do
      src = "module Sized\n  include Comparable\n  included do\n    def size = 1\n  end\nend\n"

      expect(diffs_for(src, "size")).to contain_exactly(a_string_including("- ", "include Comparable"))
    end

    it "removes a mixin written in a block of the body" do
      src = "module Sized\n  def size = 1\n  included do\n    include Comparable\n  end\nend\n"

      expect(diffs_for(src, "size")).to contain_exactly(a_string_including("- ", "include Comparable"))
    end

    it "attributes a mixin in a singleton class to that singleton class's first method" do
      src = "class C\n  def a = 1\n  class << self\n    include Foo\n    def b = 2\n  end\nend\n"

      expect(diffs_for(src, "a")).to be_empty
      expect(diffs_for(src, "b")).to contain_exactly(a_string_including("- ", "include Foo"))
    end

    it "reaches a class whose only methods sit in a singleton class" do
      src = "class Report\n  include Comparable\n  class << self\n    extend Foo\n    def build = new\n  end\nend\n"

      expect(diffs_for(src, "build")).to contain_exactly(
        a_string_including("- ", "include Comparable"), a_string_including("- ", "extend Foo")
      )
    end

    it "cuts exactly the mixin call out of the source" do
      src = "class C\n  include Foo\n  def m = 1\nend\n"
      subject = subjects_from_source(src).first

      expect(described_class.new.call(subject).map(&:mutated_source)).to eq(["class C\n  \n  def m = 1\nend\n"])
    end

    # Removing it would leave `if legacy?` dangling, which does not parse.
    it "leaves a mixin guarded by a modifier alone" do
      src = "class C\n  def a = 1\n  include Foo if legacy?\nend\n"

      expect(diffs_for(src, "a")).to be_empty
    end

    it "leaves a mixin call inside a method alone" do
      src = "class C\n  def a\n    extend Foo\n  end\nend\n"

      expect(diffs_for(src, "a")).to be_empty
    end

    it "leaves a mixin sent to another receiver alone" do
      src = "class C\n  def a = 1\n  Other.include Foo\nend\n"

      expect(diffs_for(src, "a")).to be_empty
    end
  end
end
