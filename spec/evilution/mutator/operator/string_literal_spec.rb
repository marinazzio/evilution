# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::StringLiteral do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/string_literal.rb", __dir__) }
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name, **options)
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    described_class.new(**options).call(subject)
  end

  describe "#call" do
    it 'replaces "hello" with "" and nil' do
      muts = mutations_for("returns_hello")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_hello\s+""\s+end/),
        a_string_matching(/def returns_hello\s+nil\s+end/)
      )
    end

    it 'replaces "" with "mutation" and nil' do
      muts = mutations_for("returns_empty")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_empty\s+"mutation"\s+end/),
        a_string_matching(/def returns_empty\s+nil\s+end/)
      )
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          expect { Prism.parse(mutation.mutated_source) }.not_to raise_error,
                                                                 "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "skips plain heredoc strings" do
      muts = mutations_for("returns_heredoc")

      expect(muts).to be_empty
    end

    it "skips heredoc strings with interpolation but mutates regular strings in same method" do
      muts = mutations_for("returns_heredoc_with_interpolation")

      # Only the regular string "world" (name = "world") should be mutated, not the heredoc parts
      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to all(include("<<~HEREDOC"))
      expect(mutated_sources).to include(
        a_string_matching(/name = ""\n/),
        a_string_matching(/name = nil\n/)
      )
    end

    it "mutates string literals inside heredoc interpolations" do
      muts = mutations_for("returns_heredoc_with_string_in_interpolation")

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to all(include("<<~HEREDOC"))
      expect(mutated_sources).to include(
        a_string_matching(/hello \#\{""\} world/),
        a_string_matching(/hello \#\{nil\} world/)
      )
    end

    context "with skip_heredoc_literals: true" do
      it "skips string literals inside heredoc interpolations" do
        muts = mutations_for("returns_heredoc_with_string_in_interpolation", skip_heredoc_literals: true)

        expect(muts).to be_empty
      end

      it "still mutates regular strings" do
        muts = mutations_for("returns_hello", skip_heredoc_literals: true)

        expect(muts.length).to eq(2)
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("returns_hello")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("string_literal")
      end
    end

    describe "adjacent-string concatenation" do
      it "emits a single pair of mutations for a backslash-continued chain" do
        muts = mutations_for("returns_backslash_chained")

        # Chain has 3 chunks; per-chunk mutation would yield 6 mutations and
        # each would splice into the chain incorrectly. Whole-expression
        # replacement yields 2 mutations.
        expect(muts.length).to eq(2)
        expect(muts.map(&:parse_status)).to all(eq(:ok))
      end

      it "produces parseable code for a two-chunk continued chain" do
        muts = mutations_for("returns_two_chunk_chain")

        expect(muts.length).to eq(2)
        expect(muts.map(&:parse_status)).to all(eq(:ok))
        mutated_sources = muts.map(&:mutated_source)
        expect(mutated_sources).to include(
          a_string_matching(/def returns_two_chunk_chain\s+""\s+end/),
          a_string_matching(/def returns_two_chunk_chain\s+nil\s+end/)
        )
      end

      it "replaces the whole chain with empty string or nil (not partial replacement)" do
        muts = mutations_for("returns_backslash_chained")

        mutated_sources = muts.map(&:mutated_source)
        # No leftover string fragment should survive
        expect(mutated_sources).to all(satisfy { |s| !s.include?('"alpha "') })
        expect(mutated_sources).to all(satisfy { |s| !s.include?('"beta "') })
        expect(mutated_sources).to all(satisfy { |s| !s.include?('"gamma"') })
      end

      it "also collapses same-line adjacent concatenation `\"foo\" \"bar\"` to two mutations" do
        muts = mutations_for("returns_same_line_adjacent")

        expect(muts.length).to eq(2)
        expect(muts.map(&:parse_status)).to all(eq(:ok))
        mutated_sources = muts.map(&:mutated_source)
        expect(mutated_sources).to include(
          a_string_matching(/def returns_same_line_adjacent\s+""\s+end/),
          a_string_matching(/def returns_same_line_adjacent\s+nil\s+end/)
        )
      end

      it "collapses plain-then-interpolated continued concat to two whole-expression mutations" do
        muts = mutations_for("returns_plain_plus_interp_continued")

        expect(muts.length).to eq(2)
        expect(muts.map(&:parse_status)).to all(eq(:ok))
        mutated_sources = muts.map(&:mutated_source)
        expect(mutated_sources).to include(
          a_string_matching(/def returns_plain_plus_interp_continued\s+""\s+end/),
          a_string_matching(/def returns_plain_plus_interp_continued\s+nil\s+end/)
        )
        expect(mutated_sources).to all(satisfy { |s| !s.include?("RuboCop supports target") })
        expect(mutated_sources).to all(satisfy { |s| !s.include?("`parser`. Specified target") })
      end

      it "collapses interpolated-then-plain continued concat to two whole-expression mutations" do
        muts = mutations_for("returns_interp_plus_plain_continued")

        expect(muts.length).to eq(2)
        expect(muts.map(&:parse_status)).to all(eq(:ok))
        mutated_sources = muts.map(&:mutated_source)
        expect(mutated_sources).to include(
          a_string_matching(/def returns_interp_plus_plain_continued\s+""\s+end/),
          a_string_matching(/def returns_interp_plus_plain_continued\s+nil\s+end/)
        )
      end

      it "does not collapse a plain interpolated string `\"hello #{name}\"`" do
        # Non-regression: a single quoted span containing interpolation
        # (StringNode chunk + EmbeddedStatementsNode part) must NOT be treated
        # as adjacent concat — only the inner literal chunk should be mutated,
        # the surrounding `"..." interpolation `..."` structure preserved.
        muts = mutations_for("returns_plain_interpolated")
        interp_muts = muts.select { |m| m.diff.include?("\"hello \#{name}\"") }

        # super-traversal mutates the inner `hello ` StringNode chunk into
        # two replacements (`""` and `nil`). The outer quotes and `#{name}`
        # interpolation must survive in both.
        expect(interp_muts.length).to eq(2)
        expect(interp_muts.map(&:parse_status)).to all(eq(:ok))
        interp_muts.each do |mutation|
          replaced_line = mutation.diff.lines.find { |l| l.start_with?("+") }
          expect(replaced_line).to include("\#{name}"),
                                   "Expected `\#{name}` preserved in mutated line, got: #{replaced_line.inspect}"
          # Reject whole-expression collapse: the replacement line must NOT be
          # bare `""` or `nil` (which would indicate the InterpolatedStringNode
          # itself was substituted, not just its inner chunk).
          expect(replaced_line.strip).not_to match(/\A\+\s*(""|nil)\z/),
                                             "Expected only inner chunk mutated, got whole-expression collapse: #{replaced_line.inspect}"
        end
      end

      it "does not collapse a pure-interpolation string `\"\#{a}\#{b}\"`" do
        # Non-regression for Copilot review (PR #1221): EmbeddedStatementsNode
        # parts also carry an `opening_loc` (the `#{` delimiter), so a naive
        # `parts.all? { |p| p.opening_loc }` predicate would misclassify
        # `"#{a}#{b}"` (parts = [EmbeddedStatementsNode, EmbeddedStatementsNode])
        # as adjacent concat and collapse the whole expression. The predicate
        # must only accept StringNode / InterpolatedStringNode parts.
        muts = mutations_for("returns_pure_interpolation")
        interp_muts = muts.select { |m| m.diff.include?("\"\#{a}\#{b}\"") }

        # No whole-expression collapse mutation should be emitted for this
        # node. Mutations targeting the inner literal `a = "1"` / `b = "2"`
        # are fine and counted elsewhere.
        whole_expr_collapse = interp_muts.select do |m|
          replaced_line = m.diff.lines.find { |l| l.start_with?("+") }
          !replaced_line.nil? && replaced_line.strip.match?(/\A\+\s*(""|nil)\z/)
        end
        expect(whole_expr_collapse).to be_empty,
                                       "Expected no whole-expression collapse; got: #{whole_expr_collapse.map(&:diff).inspect}"
      end
    end
  end
end
