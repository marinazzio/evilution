# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::MethodBodyToRaise do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/method_body_to_raise.rb", __dir__) }
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
    tmpfile = Tempfile.new(["method_body_to_raise", ".rb"])
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
    it "replaces a single-statement body with raise" do
      muts = mutations_for("single_statement")

      expect(mutated_bodies(muts, "single_statement")).to eq(
        ["  def single_statement(value)\n    raise\n  end\n"]
      )
    end

    it "replaces a multi-statement body with a single raise" do
      muts = mutations_for("multi_statement")

      expect(mutated_bodies(muts, "multi_statement")).to eq(
        ["  def multi_statement(items)\n    raise\n  end\n"]
      )
    end

    it "replaces the body of a singleton method" do
      muts = mutations_for("singleton")

      expect(mutated_bodies(muts, "singleton")).to eq(
        ["  def self.singleton(value)\n    raise\n  end\n"]
      )
    end

    it "replaces the body of an endless method" do
      muts = mutations_for("endless_method")

      expect(muts.map { |m| m.mutated_source[/  def endless_method.*$/] }).to eq(
        ["  def endless_method(value) = raise"]
      )
    end

    # A def-level rescue hangs the body off a BeginNode whose span covers the
    # whole `def...end`. Only the leading statements may be replaced; rewriting
    # the outer span would delete the method framing itself.
    it "replaces only the statements of a body with a rescue clause" do
      muts = mutations_for("with_rescue")

      expect(mutated_bodies(muts, "with_rescue")).to eq(
        ["  def with_rescue(value)\n    raise\n  rescue StandardError\n    nil\n  end\n"]
      )
    end

    it "replaces only the statements of a body with an ensure clause" do
      muts = mutations_for("with_ensure")

      expect(mutated_bodies(muts, "with_ensure")).to eq(
        ["  def with_ensure(value)\n    raise\n  ensure\n    cleanup\n  end\n"]
      )
    end

    it "emits nothing for an empty method body" do
      expect(mutations_for("empty_method")).to be_empty
    end

    it "emits nothing for a body that is only a rescue clause" do
      expect(mutations_for("rescue_only")).to be_empty
    end

    it "emits nothing when the body is already a bare raise" do
      expect(mutations_for("bare_raise")).to be_empty
    end

    # An abstract method mutates to a raise of a different class, which is the
    # signal RaiseArgumentStrip (#1537) owns rather than this operator.
    it "emits nothing when the body is a single raise of an error class" do
      expect(mutations_for("raise_with_class")).to be_empty
    end

    it "emits nothing when the body is a single raise with arguments" do
      expect(mutations_for("raise_with_arguments")).to be_empty
    end

    # A receiverless, argumentless call has the same shape as a bare raise;
    # only the method name separates them.
    it "mutates a body that is a single bare call other than raise" do
      muts = mutations_from_source("def bare_call\n  cleanup\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def bare_call\n  raise\nend\n"])
    end

    it "mutates a body whose raise is one statement among several" do
      muts = mutations_from_source("def guard(flag)\n  raise unless flag\n  flag\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def guard(flag)\n  raise\nend\n"])
    end

    it "mutates a body that raises through an explicit receiver" do
      muts = mutations_from_source("def delegated\n  Kernel.raise\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def delegated\n  raise\nend\n"])
    end

    # The skip rule reads one statement, so a raise standing first among several
    # is the case that separates "the body is a raise" from "the body opens with
    # one".
    it "mutates a body whose first of several statements is a bare raise" do
      muts = mutations_from_source("def two_statements(x)\n  raise\n  x\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def two_statements(x)\n  raise\nend\n"])
    end

    # Visiting one subject descends into a def nested in its body, so the outer
    # subject yields both mutations. The identical mutation reached again
    # through the inner subject is deduplicated by the runner, not here.
    it "mutates a nested def as well as its enclosing method" do
      muts = mutations_from_source("def outer\n  def inner\n    1\n  end\nend\n", method_name: "outer")

      expect(muts.map(&:mutated_source)).to contain_exactly(
        "def outer\n  raise\nend\n",
        "def outer\n  def inner\n    raise\n  end\nend\n"
      )
    end

    it "mutates each method of a class independently" do
      muts = mutations_from_source("class A\n  def one\n    1\n  end\n\n  def two\n    2\n  end\nend\n")

      expect(muts.length).to eq(2)
    end

    it "reports the mutation on the line of the def" do
      muts = mutations_for("single_statement")

      expect(muts.map(&:line)).to eq([5])
    end

    it "names the operator" do
      muts = mutations_for("single_statement")

      expect(muts.map(&:operator_name)).to eq(["method_body_to_raise"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("single_statement") + mutations_for("endless_method") +
             mutations_for("with_rescue") + mutations_for("with_ensure")

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["def"])

      muts = described_class.new.call(subject_for("single_statement"), filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
