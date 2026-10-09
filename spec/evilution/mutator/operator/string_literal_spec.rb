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

    describe "interpolated string as a whole" do
      def mutations_of(body, **options)
        Tempfile.create(["string_literal", ".rb"]) do |file|
          File.write(file.path, "class Sample\n  def value(x)\n#{body}  end\nend\n")
          described_class.new(**options).call(Evilution::AST::Parser.new.call(file.path).first)
        end
      end

      def mutated_lines(body, **options)
        mutations_of(body, **options).map { |m| m.mutated_source.lines[2].strip }
      end

      it "produces valid Ruby" do
        bodies = ["    \"a \#{x} b\"\n", "    %Q{a \#{x}}\n", "    record \"\#{x}\", x\n", "    \"\#{x}\".size\n",
                  "    \"\#{\"\#{x}\"}\"\n", "    %W[a\#{x} b]\n", "    \"a\" \"b \#{x}\"\n", "    \"\#{x || \"a\"}\#{x}\"\n"]
        mutations = bodies.flat_map { |body| mutations_of(body) }

        expect(mutations).not_to be_empty
        expect(mutations.map(&:parse_status)).to all(eq(:ok))
      end

      it "replaces the whole string with \"\" and nil, before its chunks" do
        expect(mutated_lines("    \"a \#{x} b\"\n").first(2)).to eq(['""', "nil"])
      end

      it "still mutates the chunks inside" do
        lines = mutated_lines("    \"a \#{x}\"\n")

        expect(lines).to eq(['""', "nil", "\"\"\"\#{x}\"", "\"nil\#{x}\""])
      end

      it "replaces a string that is only an interpolation" do
        expect(mutated_lines("    \"\#{x}\"\n")).to eq(['""', "nil"])
      end

      it "replaces a %() and %Q{} string" do
        expect(mutated_lines("    %(a \#{x})\n").first(2)).to eq(['""', "nil"])
        expect(mutated_lines("    %Q{a \#{x}}\n").first(2)).to eq(['""', "nil"])
      end

      it "replaces the string inside an expression" do
        expect(mutated_lines("    record \"\#{x}\", x\n")).to eq(['record "", x', "record nil, x"])
        expect(mutated_lines("    \"\#{x}\".size\n")).to eq(['"".size', "nil.size"])
      end

      it "replaces an interpolated string nested in an interpolation" do
        expect(mutated_lines("    \"\#{\"\#{x}\"}\"\n")).to eq(['""', "nil", "\"\#{\"\"}\"", "\"\#{nil}\""])
      end

      # A word of `%W[]` is not a literal of its own: `nil` there is the word "nil".
      it "does not replace a word of a %W array as a whole" do
        expect(mutated_lines("    %W[a\#{x} b]\n")).not_to include('%W["" b]', "%W[nil b]")
      end

      it "leaves an interpolated heredoc alone" do
        expect(mutated_lines("    <<~TEXT\n      a \#{x}\n    TEXT\n")).to be_empty
      end

      # Two interpolations side by side are one string, not adjacent literals:
      # the traversal goes on into them.
      it "still reaches a literal inside one of several interpolations" do
        expect(mutated_lines("    \"\#{x || \"a\"}\#{x}\"\n"))
          .to eq(['""', "nil", "\"\#{x || \"\"}\#{x}\"", "\"\#{x || nil}\#{x}\""])
      end

      it "replaces an adjacent concatenation once" do
        expect(mutated_lines("    \"a\" \"b \#{x}\"\n")).to eq(['""', "nil"])
      end
    end

    describe "command literal" do
      def mutations_of(body, **options)
        Tempfile.create(["string_literal", ".rb"]) do |file|
          File.write(file.path, "class Sample\n  def value(x)\n#{body}  end\nend\n")
          described_class.new(**options).call(Evilution::AST::Parser.new.call(file.path).first)
        end
      end

      def mutated_lines(body, **options)
        mutations_of(body, **options).map { |m| m.mutated_source.lines[2].strip }
      end

      it "replaces a backtick command with nil" do
        expect(mutated_lines("    `ls -la`\n")).to eq(["nil"])
      end

      it "replaces a %x command with nil" do
        expect(mutated_lines("    %x(ls -la)\n")).to eq(["nil"])
      end

      it "replaces an empty command with nil" do
        expect(mutated_lines("    ``\n")).to eq(["nil"])
      end

      it "replaces an interpolated command as a whole" do
        expect(mutated_lines("    `ls \#{x}`\n")).to eq(["nil"])
        expect(mutated_lines("    %x{ls \#{x}}\n")).to eq(["nil"])
      end

      it "replaces the command inside an expression" do
        expect(mutated_lines("    `ls \#{x}`.lines.size\n")).to eq(["nil.lines.size"])
      end

      # A changed command would run for real wherever an example runs it.
      it "never rewrites the text of a command" do
        expect(mutated_lines("    `ls -la`\n")).not_to include("``", '""')
        expect(mutated_lines("    `ls \#{x} -la`\n")).to eq(["nil"])
      end

      it "still mutates a string literal inside the interpolation" do
        expect(mutated_lines("    `ls \#{x || \"a\"}`\n")).to eq(["nil", "`ls \#{x || \"\"}`", "`ls \#{x || nil}`"])
      end

      it "does not replace a heredoc command" do
        expect(mutated_lines("    <<~`CMD`\n      ls -la\n    CMD\n")).to be_empty
        expect(mutated_lines("    <<~`CMD`\n      ls \#{x}\n    CMD\n")).to be_empty
      end

      # Same as a heredoc string: its interpolations are walked unless
      # skip_heredoc_literals says otherwise.
      it "mutates a string literal inside a heredoc command's interpolation" do
        body = "    <<~`CMD`\n      ls \#{x || \"a\"}\n    CMD\n"

        expect(mutations_of(body).map { |m| m.mutated_source.lines[3].strip }).to eq(["ls \#{x || \"\"}", "ls \#{x || nil}"])
      end

      it "skips a heredoc command's interpolation with skip_heredoc_literals: true" do
        body = "    <<~`CMD`\n      ls \#{x || \"a\"}\n    CMD\n"

        expect(mutations_of(body, skip_heredoc_literals: true)).to be_empty
        expect(mutated_lines("    `ls \#{x || \"a\"}`\n", skip_heredoc_literals: true).length).to eq(3)
      end

      it "produces valid Ruby" do
        bodies = ["    `ls -la`\n", "    %x(ls -la)\n", "    `ls \#{x}`.lines.size\n", "    record `ls`, x\n",
                  "    `ls \#{x || \"a\"}`\n"]
        mutations = bodies.flat_map { |body| mutations_of(body) }

        expect(mutations).not_to be_empty
        expect(mutations.map(&:parse_status)).to all(eq(:ok))
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

      it "keeps the chunks of a plain interpolated string `\"hello #{name}\"` next to its whole replacement" do
        # A single quoted span containing interpolation (StringNode chunk +
        # EmbeddedStatementsNode part) is not adjacent concat: it is replaced
        # as a whole, and the traversal still reaches the inner `hello ` chunk.
        muts = mutations_for("returns_plain_interpolated")
        interp_muts = muts.select { |m| m.diff.include?("\"hello \#{name}\"") }
        replaced_lines = interp_muts.map { |m| m.diff.lines.find { |l| l.start_with?("+") }.delete_prefix("+").strip }

        expect(interp_muts.map(&:parse_status)).to all(eq(:ok))
        expect(replaced_lines).to eq(['""', "nil", "\"\"\"\#{name}\"", "\"nil\#{name}\""])
      end

      it "does not mutate StringNode chunks inside an interpolated symbol `:\"visit_\#{type}\"`" do
        # send(:"visit_#{type}") — the inner StringNode "visit_" is a chunk of
        # an InterpolatedSymbolNode, not a free string literal. Mutating it
        # splices `""` between the `:"` and the `#{...}` opener, producing
        # `:""\#{type}"` which Ruby cannot parse.
        muts = mutations_for("returns_interpolated_symbol")
        symbol_chunk_muts = muts.select { |m| m.diff.include?(":\"visit_") }
        expect(symbol_chunk_muts).to be_empty,
                                     "Expected no symbol-chunk mutations; got: #{symbol_chunk_muts.map(&:diff).inspect}"

        # The free-string variable `type = "node"` on the prior line is still a
        # legitimate target, so the overall mutation set is non-empty.
        expect(muts).not_to be_empty
        expect(muts.map(&:parse_status)).to all(eq(:ok))
      end

      it "does not mutate StringNode chunks inside an interpolated regex `/^\#{needle}/`" do
        muts = mutations_for("returns_interpolated_regex")
        # The regex literal must survive verbatim in every mutation's source.
        # (Mutations targeting the sibling `"foobar"` string are fine; they
        # leave the regex untouched.)
        muts.each do |mutation|
          expect(mutation.mutated_source).to include("/^\#{needle}/"),
                                             "Regex chunk mutated; diff: #{mutation.diff.inspect}"
        end
        expect(muts.map(&:parse_status)).to all(eq(:ok))
      end

      it "does not mutate StringNode chunks inside an interpolated x-string `` `echo \#{cmd}` ``" do
        # The command is either left as written or replaced as a whole.
        muts = mutations_for("returns_interpolated_xstring")
        muts.each do |mutation|
          command_line = mutation.mutated_source[/def returns_interpolated_xstring\n.*\n(.*)\n/, 1]

          expect(command_line).not_to be_nil, "method not found in: #{mutation.mutated_source.inspect}"
          expect(["`echo \#{cmd}`", "nil"]).to include(command_line.strip),
                                               "X-string chunk mutated; diff: #{mutation.diff.inspect}"
        end
        expect(muts.map(&:parse_status)).to all(eq(:ok))
      end

      it "does not mutate plain symbol literals" do
        muts = mutations_for("returns_plain_symbol")
        expect(muts).to be_empty
      end

      it "mutates a string literal nested inside an interpolated symbol's interpolation" do
        # visit_interpolated_symbol_node must descend into the non-string
        # parts so the `"fallback"` literal inside `#{prefix || "fallback"}`
        # is still mutated.
        muts = mutations_for("returns_symbol_interp_with_string")

        expect(muts.length).to eq(2)
        replacements = muts.map { |m| m.diff.lines.find { |l| l.start_with?("+") } }
        expect(replacements).to include(
          a_string_matching(/prefix \|\| ""/),
          a_string_matching(/prefix \|\| nil/)
        )
      end

      it "mutates a string literal nested inside an interpolated regex's interpolation" do
        muts = mutations_for("returns_regex_interp_with_string")

        expect(muts.length).to eq(2)
        replacements = muts.map { |m| m.diff.lines.find { |l| l.start_with?("+") } }
        expect(replacements).to include(
          a_string_matching(/prefix \|\| ""/),
          a_string_matching(/prefix \|\| nil/)
        )
      end

      it "mutates a string literal nested inside an interpolated x-string's interpolation" do
        muts = mutations_for("returns_xstring_interp_with_string")

        expect(muts.length).to eq(3)
        replacements = muts.map { |m| m.diff.lines.find { |l| l.start_with?("+") } }
        expect(replacements).to include(
          a_string_matching(/prefix \|\| ""/),
          a_string_matching(/prefix \|\| nil/)
        )
      end

      it "uses the \"mutation\" placeholder when an adjacent concat is all-empty" do
        # node_content_empty? must inspect every part — an all-empty adjacent
        # concat yields the non-empty `"mutation"` replacement, not `""`.
        muts = mutations_for("returns_empty_adjacent")

        expect(muts.length).to eq(2)
        mutated_sources = muts.map(&:mutated_source)
        expect(mutated_sources).to include(
          a_string_matching(/def returns_empty_adjacent\s+"mutation"\s+end/),
          a_string_matching(/def returns_empty_adjacent\s+nil\s+end/)
        )
      end

      it "replaces a pure-interpolation string `\"\#{a}\#{b}\"` as a whole, once" do
        # EmbeddedStatementsNode parts also carry an `opening_loc` (the `#{`
        # delimiter), so a naive `parts.all? { |p| p.opening_loc }` predicate
        # would misclassify `"#{a}#{b}"` as adjacent concat. Either way the
        # string is replaced once, by `""` and by `nil`.
        muts = mutations_for("returns_pure_interpolation")
        interp_muts = muts.select { |m| m.diff.include?("\"\#{a}\#{b}\"") }
        replaced_lines = interp_muts.map { |m| m.diff.lines.find { |l| l.start_with?("+") }.delete_prefix("+").strip }

        expect(replaced_lines).to eq(['""', "nil"])
      end
    end
  end
end
