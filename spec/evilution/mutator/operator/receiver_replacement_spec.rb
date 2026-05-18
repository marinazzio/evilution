# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ReceiverReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/receiver_replacement.rb", __dir__) }
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name)
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subject)
  end

  describe "#call" do
    it "drops self from self.method" do
      muts = mutations_for("with_self")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("  def with_self\n    name\n  end")
    end

    it "drops self from self.method(args)" do
      muts = mutations_for("self_with_args")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("compute(x)")
      expect(muts.first.mutated_source).not_to include("self.compute")
    end

    it "drops self from self.method with block" do
      muts = mutations_for("self_with_block")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("tap { |x| x }")
      expect(muts.first.mutated_source).not_to include("self.tap")
    end

    it "skips calls with non-self receiver" do
      muts = mutations_for("no_self")

      expect(muts).to be_empty
    end

    it "skips calls without explicit receiver" do
      muts = mutations_for("implicit_self")

      expect(muts).to be_empty
    end

    it "drops self from self.setter=" do
      muts = mutations_for("self_setter")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("  def self_setter(val)\n    name = val\n  end")
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "Invalid Ruby produced for #{mutation}: #{result.errors.map(&:message)}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("with_self")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("receiver_replacement")
      end
    end

    # Kills the trailing `super` deletion: traversal must descend into a
    # self-call nested inside another self-call's arguments.
    it "mutates self-calls nested inside another self-call's arguments" do
      src = "class C\n  def m(x)\n    self.outer(self.inner(x))\n  end\nend"
      tmpfile = Tempfile.new(["receiver", ".rb"])
      tmpfile.write(src)
      tmpfile.flush
      subjects = Evilution::AST::Parser.new.call(tmpfile.path)
      subj = subjects.find { |s| s.name.end_with?("#m") }

      muts = described_class.new.call(subj)
      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_including("outer(self.inner(x))"),
        a_string_including("self.outer(inner(x))")
      )
    ensure
      tmpfile&.close
      tmpfile&.unlink
    end

    describe "Ruby-keyword-collision safety" do
      # `self.class` -> bare `class` is a syntax error because `class` is a
      # reserved keyword for class definition. Same for `self.then`, etc.
      # Stripping the receiver from any call whose name is reserved produces
      # unparseable code; skip those mutations entirely.

      it "skips self.class (bare expression)" do
        muts = mutations_for("self_class_bare")

        expect(muts).to be_empty
      end

      it "skips self.class in a chained call (self.class.new)" do
        muts = mutations_for("self_class_chained")
        # No mutation on the inner self.class. A mutation on `self.class.new`
        # itself doesn't apply (no SelfNode receiver on the outer .new call,
        # the receiver is the inner CallNode), so the method has no mutations.
        expect(muts).to be_empty
      end

      it "skips self.class on the LHS of a constant path (self.class::Handler)" do
        muts = mutations_for("self_class_const_path")

        expect(muts).to be_empty
      end

      it "skips self.then chained with a block" do
        muts = mutations_for("self_then_chained")

        expect(muts).to be_empty
      end

      it "skips self.class as an argument (is_a?(self.class))" do
        muts = mutations_for("is_a_self_class")
        # The argument's self.class is skipped. The outer `other.is_a?(...)`
        # has a non-self receiver, so it's also skipped.
        expect(muts).to be_empty
      end

      it "skips writer calls whose base name is reserved (self.class = value)" do
        # Prism CallNode name is `:class=` (with the `=` suffix). Stripping
        # `self.` produces `class = value`, which Ruby's parser rejects
        # because `class` is the class-definition keyword.
        muts = mutations_for("self_class_writer")

        expect(muts).to be_empty
      end

      it "skips writer calls for any reserved-keyword base name (self.then = value)" do
        muts = mutations_for("self_then_writer")

        expect(muts).to be_empty
      end
    end
  end
end
