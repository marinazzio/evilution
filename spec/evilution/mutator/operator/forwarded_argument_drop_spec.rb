# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ForwardedArgumentDrop do
  def mutations_for(method_source, filter: nil)
    tmpfile = Tempfile.new(["forwarded_argument_drop", ".rb"])
    tmpfile.write("class Proxy < Base\n#{method_source}end\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  # The line each mutation rewrote.
  def mutated_lines(muts)
    muts.map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  # The whole class body of each mutant, for rewrites that span several lines.
  def mutated_bodies(muts)
    muts.map { |m| m.mutated_source[/\Aclass Proxy < Base\n(.*)end\n\z/m, 1] }
  end

  describe "#call" do
    context "with anonymous parameters forwarded one by one" do
      it "drops the anonymous rest and the anonymous keyword rest in turn" do
        muts = mutations_for("  def call(*, **, &) = target.call(*, **, &)\n")

        expect(mutated_lines(muts)).to eq(
          [
            "def call(*, **, &) = target.call(**, &)",
            "def call(*, **, &) = target.call(*, &)"
          ]
        )
      end

      it "keeps the arguments written before them" do
        muts = mutations_for("  def call(name, *, **) = target.public_send(name, *, **)\n")

        expect(mutated_lines(muts)).to eq(
          [
            "def call(name, *, **) = target.public_send(name, **)",
            "def call(name, *, **) = target.public_send(name, *)"
          ]
        )
      end

      it "drops an anonymous keyword rest written after a keyword argument" do
        muts = mutations_for("  def call(**) = target.call(strict: true, **)\n")

        expect(mutated_lines(muts)).to eq(["def call(**) = target.call(strict: true)"])
      end

      it "drops them from a super call" do
        muts = mutations_for("  def call(*, **) = super(*, **)\n")

        expect(mutated_lines(muts)).to eq(["def call(*, **) = super(**)", "def call(*, **) = super(*)"])
      end

      it "drops them from a yield" do
        muts = mutations_for("  def call(*, **) = yield(*, **)\n")

        expect(mutated_lines(muts)).to eq(["def call(*, **) = yield(**)", "def call(*, **) = yield(*)"])
      end

      it "drops them from a call inside a block" do
        muts = mutations_for("  def call(*, **) = targets.each { |target| target.call(*, **) }\n")

        expect(mutated_lines(muts)).to eq(
          [
            "def call(*, **) = targets.each { |target| target.call(**) }",
            "def call(*, **) = targets.each { |target| target.call(*) }"
          ]
        )
      end

      # Dropping the only argument leaves an empty list, which is the mutant
      # ArgumentListRemoval emits; a block pass does not count, since that
      # operator keeps it too.
      it "emits nothing when the anonymous parameter is the only argument" do
        expect(mutations_for("  def call(*) = target.call(*)\n")).to be_empty
        expect(mutations_for("  def call(**) = target.call(**)\n")).to be_empty
        expect(mutations_for("  def call(*, &) = target.call(*, &)\n")).to be_empty
      end

      # Named splats are unwrapped by SplatOperator and removed from the
      # signature by KeywordArgument.
      it "emits nothing for named splats" do
        muts = mutations_for("  def call(*args, **opts, &blk) = target.call(*args, **opts, &blk)\n")

        expect(muts).to be_empty
      end

      it "drops them from a call nested in the arguments of a super or a yield" do
        muts = mutations_for("  def call(*, **)\n    super(wrap(*, **))\n    yield(wrap(*, **))\n  end\n")

        expect(mutated_bodies(muts)).to eq(
          [
            "  def call(*, **)\n    super(wrap(**))\n    yield(wrap(*, **))\n  end\n",
            "  def call(*, **)\n    super(wrap(*))\n    yield(wrap(*, **))\n  end\n",
            "  def call(*, **)\n    super(wrap(*, **))\n    yield(wrap(**))\n  end\n",
            "  def call(*, **)\n    super(wrap(*, **))\n    yield(wrap(*))\n  end\n"
          ]
        )
      end

      it "emits nothing for a call without arguments" do
        expect(mutations_for("  def call(*) = target.call\n")).to be_empty
      end
    end

    context "with all arguments forwarded by ..." do
      # `*`, `**` and `&` cannot be written under a `...` signature, so the
      # signature is spelled out as the three parts and one of them is left
      # out at the call.
      it "stops forwarding each part in turn" do
        muts = mutations_for("  def call(...) = target.call(...)\n")

        expect(mutated_lines(muts)).to eq(
          [
            "def call(*, **, &) = target.call(**, &)",
            "def call(*, **, &) = target.call(*, &)",
            "def call(*, **, &) = target.call(*, **)"
          ]
        )
      end

      it "keeps the parameters and arguments written before the dots" do
        muts = mutations_for("  def call(name, strict = true, ...) = target.public_send(name, ...)\n")

        expect(mutated_lines(muts)).to eq(
          [
            "def call(name, strict = true, *, **, &) = target.public_send(name, **, &)",
            "def call(name, strict = true, *, **, &) = target.public_send(name, *, &)",
            "def call(name, strict = true, *, **, &) = target.public_send(name, *, **)"
          ]
        )
      end

      it "rewrites a body spread over several lines" do
        muts = mutations_for("  def call(...)\n    log\n    target.call(...)\n  end\n")

        expect(mutated_bodies(muts)).to eq(
          [
            "  def call(*, **, &)\n    log\n    target.call(**, &)\n  end\n",
            "  def call(*, **, &)\n    log\n    target.call(*, &)\n  end\n",
            "  def call(*, **, &)\n    log\n    target.call(*, **)\n  end\n"
          ]
        )
      end

      # One use loses a part per mutant; the others keep forwarding everything.
      it "mutates each use separately when the dots are forwarded twice" do
        muts = mutations_for("  def call(...)\n    first(...)\n    second(...)\n  end\n")

        expect(mutated_bodies(muts)).to eq(
          [
            "  def call(*, **, &)\n    first(**, &)\n    second(*, **, &)\n  end\n",
            "  def call(*, **, &)\n    first(*, &)\n    second(*, **, &)\n  end\n",
            "  def call(*, **, &)\n    first(*, **)\n    second(*, **, &)\n  end\n",
            "  def call(*, **, &)\n    first(*, **, &)\n    second(**, &)\n  end\n",
            "  def call(*, **, &)\n    first(*, **, &)\n    second(*, &)\n  end\n",
            "  def call(*, **, &)\n    first(*, **, &)\n    second(*, **)\n  end\n"
          ]
        )
      end

      it "rewrites a super call" do
        muts = mutations_for("  def call(...) = super(...)\n")

        expect(mutated_lines(muts)).to eq(
          [
            "def call(*, **, &) = super(**, &)",
            "def call(*, **, &) = super(*, &)",
            "def call(*, **, &) = super(*, **)"
          ]
        )
      end

      it "rewrites a use inside a block" do
        muts = mutations_for("  def call(...) = targets.each { |target| target.call(...) }\n")

        expect(mutated_lines(muts).first).to eq(
          "def call(*, **, &) = targets.each { |target| target.call(**, &) }"
        )
        expect(muts.length).to eq(3)
      end

      it "emits nothing when the dots are never forwarded" do
        muts = mutations_for("  def call(...)\n    target.call\n  end\n")

        expect(muts).to be_empty
      end

      it "emits nothing for an empty method" do
        expect(mutations_for("  def call(...)\n  end\n")).to be_empty
        expect(mutations_for("  def call\n  end\n")).to be_empty
      end

      it "rewrites a use nested in the arguments of a super call" do
        muts = mutations_for("  def call(...) = super(wrap(...))\n")

        expect(mutated_lines(muts).first).to eq("def call(*, **, &) = super(wrap(**, &))")
      end

      # A method defined in the body forwards its own arguments; the outer
      # signature has nothing to do with them.
      it "keeps the dots of a method defined in the body apart" do
        muts = mutations_for("  def call(...)\n    def inner(...) = second(...)\n    first(...)\n  end\n")

        expect(mutated_bodies(muts)).to eq(
          [
            "  def call(*, **, &)\n    def inner(...) = second(...)\n    first(**, &)\n  end\n",
            "  def call(*, **, &)\n    def inner(...) = second(...)\n    first(*, &)\n  end\n",
            "  def call(*, **, &)\n    def inner(...) = second(...)\n    first(*, **)\n  end\n",
            "  def call(...)\n    def inner(*, **, &) = second(**, &)\n    first(...)\n  end\n",
            "  def call(...)\n    def inner(*, **, &) = second(*, &)\n    first(...)\n  end\n",
            "  def call(...)\n    def inner(*, **, &) = second(*, **)\n    first(...)\n  end\n"
          ]
        )
      end

      it "emits nothing for a method with ordinary parameters" do
        muts = mutations_for("  def call(name, strict: true) = target.call(name, strict: strict)\n")

        expect(muts).to be_empty
      end
    end

    it "produces parseable mutations" do
      muts = mutations_for("  def call(...)\n    def inner(name, *, **) = second(name, *, **)\n    first(...)\n  end\n")

      expect(muts.map(&:parse_status)).to eq(%i[ok ok ok ok ok])
    end

    it "sets the operator name" do
      muts = mutations_for("  def call(...) = target.call(...)\n")

      expect(muts.map(&:operator_name).uniq).to eq(["forwarded_argument_drop"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=call}"])

      muts = mutations_for("  def run(*, **) = target.call(*, **)\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(2)
    end
  end
end
