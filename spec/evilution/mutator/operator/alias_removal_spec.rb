# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::AliasRemoval do
  def subjects_for(source)
    tmpfile = Tempfile.new(["alias_removal", ".rb"])
    tmpfile.write(source)
    tmpfile.flush
    yield Evilution::AST::Parser.new.call(tmpfile.path)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutations_for(source, method_name, filter: nil)
    subjects_for(source) do |subjects|
      subject = subjects.find { |s| s.name.end_with?("##{method_name}", ".#{method_name}") }
      described_class.new.call(subject, filter: filter)
    end
  end

  # The source of each mutant with blank lines dropped, so an expectation
  # reads as the class that would load.
  def mutated_sources(muts)
    muts.map { |m| m.mutated_source.lines.reject { |line| line.strip.empty? }.join }
  end

  let(:source) do
    "class Collection\n  def size = 1\n  alias length size\n  alias_method :count, :size\n\n  def each = 2\nend\n"
  end

  describe "#call" do
    it "drops each alias declaration of a class through its first method" do
      muts = mutations_for(source, "size")

      expect(mutated_sources(muts)).to eq(
        [
          "class Collection\n  def size = 1\n  alias_method :count, :size\n  def each = 2\nend\n",
          "class Collection\n  def size = 1\n  alias length size\n  def each = 2\nend\n"
        ]
      )
    end

    # The declarations belong to no method, so they are attributed to one
    # subject only; emitting them per method would repeat the same mutant.
    it "does not repeat the mutations for later methods" do
      expect(mutations_for(source, "each")).to be_empty
    end

    it "drops symbol, string and parenthesised forms" do
      src = "class C\n  def a = 1\n  alias :b :a\n  alias_method \"c\", \"a\"\n  alias_method(:d, :a)\nend\n"

      expect(mutations_for(src, "a").length).to eq(3)
    end

    it "drops an alias in a module and in a singleton class" do
      expect(mutations_for("module M\n  def a = 1\n  alias b a\nend\n", "a").length).to eq(1)
      expect(mutations_for("class C\n  class << self\n    def a = 1\n    alias b a\n  end\nend\n", "a").length).to eq(1)
    end

    it "attributes an alias to the innermost enclosing scope" do
      src = "module M\n  def self.top = 1\n\n  class C\n    def a = 1\n    alias b a\n  end\nend\n"

      expect(mutations_for(src, "top")).to be_empty
      expect(mutations_for(src, "a").length).to eq(1)
    end

    it "drops an alias declared in a block of the body" do
      src = "module Sized\n  def a = 1\n  included do\n    alias_method :b, :a\n  end\nend\n"

      expect(mutations_for(src, "a").length).to eq(1)
    end

    it "attributes an alias after a nested class to its own scope" do
      src = "class Outer\n  class Inner\n    def i = 1\n  end\n\n  def o = 2\n  alias p o\nend\n"

      expect(mutations_for(src, "i")).to be_empty
      expect(mutations_for(src, "o").length).to eq(1)
    end

    # A top-level alias sits in no class; borrowing an unrelated method would
    # run its mutant against tests that never load it.
    it "leaves a top-level alias alone" do
      expect(mutations_for("alias b a
class C
  def a = 1
end
", "a")).to be_empty
    end

    it "leaves other calls in the body alone" do
      expect(mutations_for("class C
  def a = 1
  attr_reader :b
  include Comparable
end
", "a")).to be_empty
    end

    # A method body is reached by its own subject and its alias_method call
    # by the generic call operators.
    it "leaves an alias_method call inside a method alone" do
      src = "class C\n  def a = 1\n  def setup\n    alias_method :b, :a\n  end\nend\n"

      expect(mutations_for(src, "a")).to be_empty
      expect(mutations_for(src, "setup")).to be_empty
    end

    it "leaves alias_method sent to another receiver alone" do
      expect(mutations_for("class C\n  def a = 1\n  Other.alias_method :b, :a\nend\n", "a")).to be_empty
    end

    it "leaves global variable aliases alone" do
      expect(mutations_for("class C\n  def a = 1\n  alias $new $old\nend\n", "a")).to be_empty
    end

    it "emits nothing for a class without aliases" do
      expect(mutations_for("class C\n  def a = 1\nend\n", "a")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for(source, "size")

      expect(muts.map(&:parse_status)).to eq(%i[ok ok])
    end

    it "sets the operator name" do
      expect(mutations_for(source, "size").map(&:operator_name).uniq).to eq(["alias_removal"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=alias_method}"])

      muts = mutations_for(source, "size", filter: filter)

      expect(mutated_sources(muts)).to eq(["class Collection\n  def size = 1\n  alias_method :count, :size\n  def each = 2\nend\n"])
      expect(filter.skipped_count).to eq(1)
    end
  end
end
