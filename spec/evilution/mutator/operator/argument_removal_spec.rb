# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ArgumentRemoval do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/argument_call.rb", __dir__) }
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
    it "removes each argument from a two-arg call" do
      muts = mutations_for("two_args")

      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?("obj.compute(b)") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("obj.compute(a)") }).to be true
    end

    it "removes each argument from a three-arg call" do
      muts = mutations_for("three_args")

      expect(muts.length).to eq(3)
      expect(muts.any? { |m| m.mutated_source.include?("process(b, c)") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("process(a, c)") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("process(a, b)") }).to be true
    end

    it "skips calls with a single argument" do
      muts = mutations_for("single_arg")

      expect(muts).to be_empty
    end

    it "skips calls with no arguments" do
      muts = mutations_for("no_args")

      expect(muts).to be_empty
    end

    it "skips calls with splat arguments" do
      muts = mutations_for("with_splat")

      expect(muts).to be_empty
    end

    it "skips calls with keyword arguments" do
      muts = mutations_for("with_kwargs")

      expect(muts).to be_empty
    end

    it "skips index-assignment calls (hash/array []=)" do
      expect(mutations_for("index_assign")).to be_empty
      expect(mutations_for("multi_index_assign")).to be_empty
      expect(mutations_for("array_index_assign")).to be_empty
    end

    it "skips a multi-arg call when one positional slot is a splat" do
      # `bar(a, *rest)` has two arguments but the second is a splat — the
      # positional-only guard must reject it (not just splats in single-arg
      # calls).
      muts = mutations_for("splat_among_positional")

      expect(muts).to be_empty
    end

    it "skips a multi-arg call when one positional slot is a keyword hash" do
      # `bar(a, key: val)` has two arguments but the second is a keyword hash.
      muts = mutations_for("kwarg_among_positional")

      expect(muts).to be_empty
    end

    it "recurses into argument expressions to mutate a nested call" do
      # `outer(inner(a, b), c)`: the outer call yields 2 mutations and the
      # nested `inner(a, b)` call yields 2 more — only reached when the
      # visitor recurses into the argument expressions.
      muts = mutations_for("nested_call")

      expect(muts.length).to eq(4)
      expect(muts.any? { |m| m.mutated_source.include?("outer(inner(b), c)") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("outer(inner(a), c)") }).to be true
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
      muts = mutations_for("two_args")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("argument_removal")
      end
    end

    describe "heredoc-anchored arguments" do
      # Two paths through the heredoc safety logic:
      #   1. Replacement is heredoc-free (e.g. removing the heredoc arg leaves
      #      a plain literal): byte range extended past the heredoc body, the
      #      mutation parses cleanly.
      #   2. Replacement re-references a kept heredoc anchor: byte-range
      #      extension would strip the kept heredoc's body. Skip rather than
      #      emit unparseable bytes.

      it "produces a parseable mutation when the heredoc arg is removed" do
        muts = mutations_for("heredoc_arg")

        # arg[1] removal leaves only `ArgumentError` — heredoc-free, safe to
        # extend. arg[0] removal leaves `<<~MSG.strip` — heredoc anchor in
        # replacement, skipped. Result: exactly one parseable mutation whose
        # diff drops the heredoc and replaces it with bare `ArgumentError`.
        expect(muts.length).to eq(1)
        expect(muts.first.parse_status).to eq(:ok)
        plus_line = muts.first.diff.lines.find { |l| l.start_with?("+") }
        expect(plus_line).to include("raise ArgumentError")
        minus_lines = muts.first.diff.lines.select { |l| l.start_with?("-") }
        expect(minus_lines.join).to include("<<~MSG")
      end

      it "skips both mutations on a two-heredoc call (no safe heredoc-free replacement exists)" do
        muts = mutations_for("two_heredocs")

        # Removing either arg leaves a `<<~...` in the replacement — both
        # paths trigger the skip branch. Acceptable trade-off: no unparseable
        # mutations, at the cost of these two specific mutations.
        expect(muts).to be_empty
      end

      it "does NOT skip a mutation when the replacement contains `<<` as shift, not a heredoc anchor" do
        # `raise ArgumentError, (arr << x), <<~MSG.strip`
        # Removing the 3rd arg (heredoc) leaves replacement
        # `ArgumentError, (arr << x)` — contains `<<` as a shift operator,
        # NOT a heredoc anchor. The skip heuristic must distinguish these
        # and let the mutation through.
        muts = mutations_for("shift_arg_with_heredoc")

        # Find the mutation whose `+` line keeps the shift and drops the
        # heredoc anchor (the `<<~MSG` should appear only in the `-` lines).
        shift_kept_mut = muts.find do |m|
          plus_line = m.diff.lines.find { |l| l.start_with?("+") }
          plus_line && plus_line.include?("(arr << x)") && !plus_line.include?("<<~MSG")
        end
        expect(shift_kept_mut).not_to be_nil,
                                      "Expected a mutation that keeps `arr << x` and removes the heredoc; got: " \
                                      "#{muts.map(&:diff).inspect}"
        expect(shift_kept_mut.parse_status).to eq(:ok)
      end
    end
  end
end
