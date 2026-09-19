# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::MethodBodyToSuper do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/method_body_to_super.rb", __dir__) }
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  # Instance methods are named "Class#name", singleton methods "Class.name".
  def subject_for(method_name)
    subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}", ".#{method_name}") }
  end

  def mutations_for(method_name)
    described_class.new.call(subject_for(method_name))
  end

  # Isolate the mutated method so an expectation reads as the resulting source
  # rather than a byte offset.
  def mutated_bodies(muts, method_name)
    muts.map { |m| m.mutated_source[/  def (?:self\.)?#{method_name}\b.*?\n  end\n/m] }
  end

  def mutations_from_source(inline_source, method_name: nil)
    tmpfile = Tempfile.new(["method_body_to_super", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects = subjects.select { |s| s.name.end_with?("##{method_name}", ".#{method_name}") } if method_name
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "replaces the body of an override with bare super" do
      muts = mutations_for("plain_override")

      expect(mutated_bodies(muts, "plain_override")).to eq(
        ["  def plain_override(value)\n    super\n  end\n"]
      )
    end

    it "replaces the body of an endless override" do
      muts = mutations_for("endless_override")

      expect(muts.map { |m| m.mutated_source[/  def endless_override.*$/] }).to eq(
        ["  def endless_override(value) = super"]
      )
    end

    it "replaces the body of a singleton method on an inheriting class" do
      muts = mutations_for("singleton_override")

      expect(mutated_bodies(muts, "singleton_override")).to eq(
        ["  def self.singleton_override(value)\n    super\n  end\n"]
      )
    end

    it "replaces the body of a method defined inside class << self" do
      muts = mutations_for("in_singleton_class")

      expect(muts.map { |m| m.mutated_source[/    def in_singleton_class.*?\n    end\n/m] }).to eq(
        ["    def in_singleton_class(value)\n      super\n    end\n"]
      )
    end

    # An included module sits behind the class in the ancestor chain, so it is
    # a real super target even without an explicit superclass.
    it "replaces the body of a method in a class that includes a module" do
      muts = mutations_for("mixed_in")

      expect(mutated_bodies(muts, "mixed_in")).to eq(
        ["  def mixed_in(value)\n    super\n  end\n"]
      )
    end

    it "replaces the body of a method in a class that prepends a module" do
      muts = mutations_for("prepended_over")

      expect(mutated_bodies(muts, "prepended_over")).to eq(
        ["  def prepended_over(value)\n    super\n  end\n"]
      )
    end

    it "replaces the body of a method in a module that includes another module" do
      muts = mutations_for("module_with_include")

      expect(mutated_bodies(muts, "module_with_include")).to eq(
        ["  def module_with_include(value)\n    super\n  end\n"]
      )
    end

    # `extend` mixes into the singleton class, so it supplies a super target for
    # `def self.x` but not for instance methods.
    it "replaces the body of a singleton method in a class that extends a module" do
      muts = mutations_for("singleton_with_extend")

      expect(mutated_bodies(muts, "singleton_with_extend")).to eq(
        ["  def self.singleton_with_extend(value)\n    super\n  end\n"]
      )
    end

    it "emits nothing for an instance method whose class only extends a module" do
      expect(mutations_for("instance_in_extender")).to be_empty
    end

    it "emits nothing for a class with no superclass and no mixins" do
      expect(mutations_for("no_parent")).to be_empty
    end

    it "emits nothing for a method in a plain module" do
      expect(mutations_for("module_method")).to be_empty
    end

    it "emits nothing for a top-level method" do
      expect(mutations_from_source("def orphan(value)\n  value\nend\n")).to be_empty
    end

    # MethodBodyReplacement already mutates these to bare super; emitting here
    # would attribute one mutation to two operators.
    it "emits nothing when the body already calls super" do
      expect(mutations_for("calls_super")).to be_empty
    end

    # A nested def opens its own method scope, so its `super` belongs to it and
    # says nothing about whether the enclosing body reaches for a parent.
    it "mutates a method whose only super call sits inside a nested def" do
      muts = mutations_from_source(
        "class A < B\n  def outer(value)\n    def inner\n      super\n    end\n    value\n  end\nend\n",
        method_name: "outer"
      )

      expect(muts.map(&:mutated_source)).to eq(
        ["class A < B\n  def outer(value)\n    super\n  end\nend\n"]
      )
    end

    # A block does not open a method scope: a `super` inside one still refers to
    # the method it is written in.
    it "emits nothing when super is called inside a block" do
      muts = mutations_from_source(
        "class A < B\n  def call(values)\n    values.map { super }\n  end\nend\n"
      )

      expect(muts).to be_empty
    end

    it "emits nothing when the body calls super with explicit arguments" do
      expect(mutations_for("calls_super_with_arguments")).to be_empty
    end

    it "replaces a class << self body when the class extends a module" do
      muts = mutations_for("singleton_class_with_extend")

      expect(muts.map { |m| m.mutated_source[/    def singleton_class_with_extend.*?\n    end\n/m] }).to eq(
        ["    def singleton_class_with_extend(value)\n      super\n    end\n"]
      )
    end

    # include mixes into instances, so it leaves a singleton method without a
    # super target even though the same class qualifies for instance methods.
    it "emits nothing for a class << self body when the class only includes a module" do
      expect(mutations_for("singleton_class_with_include")).to be_empty
    end

    it "emits nothing when the mixin call carries no arguments" do
      muts = mutations_from_source("class A\n  include\n\n  def call(value)\n    value\n  end\nend\n")

      expect(muts).to be_empty
    end

    it "emits nothing when the mixin call has an explicit receiver" do
      muts = mutations_from_source("class A\n  Other.include B\n\n  def call(value)\n    value\n  end\nend\n")

      expect(muts).to be_empty
    end

    it "emits nothing for an empty method body" do
      expect(mutations_for("empty_override")).to be_empty
    end

    it "emits nothing for a body that is only a rescue clause" do
      expect(mutations_for("rescue_only")).to be_empty
    end

    # A def-level rescue hangs the body off a BeginNode whose span covers the
    # whole `def...end`; only the leading statements may be replaced.
    it "replaces only the statements of a body with a rescue clause" do
      muts = mutations_for("with_rescue")

      expect(mutated_bodies(muts, "with_rescue")).to eq(
        ["  def with_rescue(value)\n    super\n  rescue StandardError\n    nil\n  end\n"]
      )
    end

    it "replaces only the statements of a body with an ensure clause" do
      muts = mutations_for("with_ensure")

      expect(mutated_bodies(muts, "with_ensure")).to eq(
        ["  def with_ensure(value)\n    super\n  ensure\n    cleanup\n  end\n"]
      )
    end

    # Visiting the outer subject descends into the def nested in its body. The
    # same mutation reached again through the inner subject is deduplicated by
    # the runner, not here, so the outer subject is asked on its own.
    it "mutates a nested def as well as its enclosing method" do
      muts = mutations_from_source(
        "class A < B\n  def outer\n    def inner\n      1\n    end\n  end\nend\n",
        method_name: "outer"
      )

      expect(muts.map(&:mutated_source)).to contain_exactly(
        "class A < B\n  def outer\n    super\n  end\nend\n",
        "class A < B\n  def outer\n    def inner\n      super\n    end\n  end\nend\n"
      )
    end

    it "finds a qualifying class nested inside a module" do
      muts = mutations_from_source(
        "module Wrapper\n  class Inner < Base\n    def call(value)\n      value\n    end\n  end\nend\n"
      )

      expect(muts.map(&:mutated_source)).to eq(
        ["module Wrapper\n  class Inner < Base\n    def call(value)\n      super\n    end\n  end\nend\n"]
      )
    end

    # Descending into a `class << self` body is what finds a scope nested
    # inside it rather than stopping at the class around it.
    it "finds a qualifying class nested inside a class << self body" do
      muts = mutations_from_source(
        "class Outer\n  class << self\n    class Inner < Base\n      def call(value)\n        " \
        "value\n      end\n    end\n  end\nend\n"
      )

      expect(muts.length).to eq(1)
    end

    it "mutates the method of the innermost enclosing class" do
      muts = mutations_from_source(
        "class Outer < Base\n  class Inner\n    def only_here(value)\n      value\n    end\n  end\nend\n"
      )

      expect(muts).to be_empty
    end

    it "reports the mutation on the line of the def" do
      muts = mutations_for("plain_override")

      expect(muts.map(&:line)).to eq([17])
    end

    it "names the operator" do
      muts = mutations_for("plain_override")

      expect(muts.map(&:operator_name)).to eq(["method_body_to_super"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("plain_override") + mutations_for("endless_override") +
             mutations_for("with_rescue") + mutations_for("with_ensure")

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["def"])

      muts = described_class.new.call(subject_for("plain_override"), filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
