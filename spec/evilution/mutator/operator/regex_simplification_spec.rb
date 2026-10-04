# frozen_string_literal: true

require "tempfile"

RSpec.describe Evilution::Mutator::Operator::RegexSimplification do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/regex_simplification.rb", __dir__) }
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

  # Builds a one-method file whose body is `s.match?(<regex>)` and returns the
  # mutations the operator emits for it. Backed by a real tempfile because the
  # operator reads the subject's file path.
  def mutations_for_regex(regex_literal)
    tmpfile = Tempfile.new(["regex_simplification", ".rb"])
    tmpfile.write("def probe(s)\n  s.match?(#{regex_literal})\nend\n")
    tmpfile.flush
    @tmpfiles ||= []
    @tmpfiles << tmpfile
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  end

  after do
    Array(@tmpfiles).each do |f|
      f.close
      f.unlink
    end
  end

  describe "#call" do
    context "quantifier removal" do
      it "removes + quantifier" do
        muts = mutations_for("with_plus_quantifier")

        expect(muts.any? { |m| m.mutated_source.include?('/\d/') }).to be true
      end

      it "removes * quantifier" do
        muts = mutations_for("with_star_quantifier")

        expect(muts.any? { |m| m.mutated_source.include?('/\s/') }).to be true
      end

      it "removes ? quantifier" do
        muts = mutations_for("with_question_quantifier")

        expect(muts.any? { |m| m.mutated_source.include?('/\d/') }).to be true
      end

      it "removes {n,m} quantifier" do
        muts = mutations_for("with_curly_quantifier")

        expect(muts.any? { |m| m.mutated_source.include?('/\d/') }).to be true
      end

      it "does not remove escaped quantifier" do
        muts = mutations_for("with_escaped_quantifier")

        expect(muts.none? { |m| m.mutated_source.include?('/\d/') }).to be true
      end
    end

    context "anchor removal" do
      it "removes ^ and $ anchors" do
        muts = mutations_for("with_anchors")

        expect(muts.any? { |m| m.mutated_source.include?("/foo$/") }).to be true
        expect(muts.any? { |m| m.mutated_source.include?("/^foo/") }).to be true
      end

      it 'removes \A and \z anchors' do
        muts = mutations_for("with_backslash_anchors")

        expect(muts.any? { |m| m.mutated_source.include?('/foo\z/') }).to be true
        expect(muts.any? { |m| m.mutated_source.include?('/\Afoo/') }).to be true
      end
    end

    context "character class range removal" do
      it "removes range dash from [a-z]" do
        muts = mutations_for("with_character_class_range")

        expect(muts.any? { |m| m.mutated_source.include?("/[az]/") }).to be true
      end

      it "does not remove leading dash in negated class [^-a]" do
        muts = mutations_for("with_negated_class_leading_dash")

        expect(muts.none? { |m| m.mutated_source.include?("/[^a]/") }).to be true
      end

      it "does not remove leading dash in class [-a]" do
        muts = mutations_for("with_class_leading_dash")

        expect(muts.none? { |m| m.mutated_source.include?("/[a]/") }).to be true
      end

      it "removes each range dash from [a-zA-Z0-9]" do
        muts = mutations_for("with_multiple_ranges")
        sources = muts.map(&:mutated_source)

        expect(sources.any? { |s| s.include?("/[azA-Z0-9]/") }).to be true
        expect(sources.any? { |s| s.include?("/[a-zAZ0-9]/") }).to be true
        expect(sources.any? { |s| s.include?("/[a-zA-Z09]/") }).to be true
      end
    end

    context "combined patterns" do
      it "produces multiple mutations for pattern with quantifiers, anchors, and ranges" do
        muts = mutations_for("with_combined")

        expect(muts.length).to be >= 4
      end
    end

    it "skips methods without regexps" do
      muts = mutations_for("no_regexp")

      expect(muts).to be_empty
    end

    it "skips empty regexp" do
      muts = mutations_for("with_empty_regexp")

      expect(muts).to be_empty
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
      muts = mutations_for("with_plus_quantifier")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("regex_simplification")
      end
    end

    context "anchor guard" do
      it "emits no anchor mutations for a regex with no anchors" do
        muts = mutations_for_regex("/abc/")

        expect(muts).to be_empty
      end
    end

    context "character class range scanning" do
      it "does not treat a dash after the class close as a range" do
        muts = mutations_for_regex("/[a-z]-x/")

        expect(muts.length).to eq(1)
        expect(muts.first.mutated_source).to include("/[az]-x/")
      end

      it "does not treat an escaped dash inside a class as a range" do
        muts = mutations_for_regex('/[a\-z]/')

        expect(muts).to be_empty
      end

      it "skips an escaped dash and still finds a later real range" do
        muts = mutations_for_regex('/[a\-z0-9]/')
        sources = muts.map(&:mutated_source)

        expect(muts.length).to eq(1)
        expect(sources).to include(a_string_including('/[a\-z09]/'))
      end

      it "skips both escape sequences without misreading the second escaped dash" do
        muts = mutations_for_regex('/[\d\-x]/')

        expect(muts).to be_empty
      end

      it "emits a range mutation only for an actual range dash" do
        muts = mutations_for_regex("/[a-z]/")

        expect(muts.length).to eq(1)
        expect(muts.first.mutated_source).to include("/[az]/")
      end

      # Ruby reads an unescaped `]` right after `[^` as a class member (and
      # warns about it); regexp_parser reads an empty class instead. Rather
      # than guess, the pattern gets no mutants.
      it "emits nothing for an unescaped bracket leading a negated class" do
        expect(mutations_for_regex("/[^]a-z]/")).to be_empty
      end

      it "does not treat a dash directly before the class close as a range" do
        muts = mutations_for_regex("/[a-]b/")

        expect(muts).to be_empty
      end

      it "does not mutate a literal plus inside a character class" do
        muts = mutations_for_regex("/[a+b]z/")

        expect(muts).to be_empty
      end

      it "removes a quantifier following a character class" do
        muts = mutations_for_regex("/[a-z]+/")
        sources = muts.map(&:mutated_source)

        expect(sources).to include(a_string_including("/[az]+/"))
        expect(sources).to include(a_string_including("/[a-z]/"))
      end

      it "skips an escaped close-bracket when locating the class end" do
        muts = mutations_for_regex('/[a\]+]z/')

        expect(muts).to be_empty
      end
    end

    # The pattern's own structure decides what is a quantifier or an anchor:
    # group syntax, comments and property escapes contain the same characters
    # without being either.
    context "pattern structure" do
      def mutated_patterns(regex_literal)
        mutations_for_regex(regex_literal).map { |m| m.mutated_source[/match\?\((.*)\)/m, 1] }
      end

      it "does not read the ? of a group opener as a quantifier" do
        expect(mutated_patterns("/(?:ab)+/")).to eq(["/(?:ab)/"])
        expect(mutated_patterns("/(?<name>x)/")).to be_empty
        expect(mutated_patterns("/(?=a)b/")).to be_empty
        expect(mutated_patterns("/(?!a)(?<=b)(?<!c)(?>d)/")).to be_empty
      end

      it "leaves the inside of a comment group alone" do
        expect(mutated_patterns("/x(?#comment ^$+)y/")).to be_empty
      end

      it "leaves comments and whitespace of an extended pattern alone" do
        expect(mutated_patterns("/a # ^ and $ here\n  b+/x")).to eq(["/a # ^ and $ here\n  b/x"])
      end

      # Ruby reads `{2,}?` as one lazy interval; removing only `{2,}` would
      # leave its lazy marker behind as a new `?` quantifier.
      it "removes a lazy interval as one quantifier" do
        expect(mutated_patterns("/a{2,}?/")).to eq(["/a/"])
      end

      it "keeps quantifiers apart that are not a lazy interval" do
        expect(mutated_patterns("/a{2}b?/")).to eq(["/ab?/", "/a{2}b/"])
        expect(mutated_patterns("/a{2}+/")).to eq(["/a+/", "/a{2}/"])
        expect(mutated_patterns("/a+??/")).to eq(["/a?/", "/a+?/"])
        expect(mutated_patterns("/a+b{2,}?/")).to eq(["/ab{2,}?/", "/a+b/"])
      end

      it "removes lazy and possessive quantifiers whole" do
        expect(mutated_patterns("/a+?b*+/")).to eq(["/ab*+/", "/a+?b/"])
      end

      it "leaves the negation of a property escape alone" do
        expect(mutated_patterns("/\\p{^Alpha}/")).to be_empty
      end

      it "removes string anchors and leaves other assertions alone" do
        expect(mutated_patterns("/\\Aa\\z/")).to eq(["/a\\z/", "/\\Aa/"])
        expect(mutated_patterns("/a\\Z/")).to eq(["/a/"])
        expect(mutated_patterns("/\\ba\\B\\G/")).to be_empty
      end

      # A quantifier that a subexpression call depends on cannot be removed
      # without the pattern failing to compile.
      it "skips a removal that leaves a pattern which no longer compiles" do
        expect(mutated_patterns("/\\A(?<p>a\\g<p>?b)\\z/")).to eq(
          ["/(?<p>a\\g<p>?b)\\z/", "/\\A(?<p>a\\g<p>?b)/"]
        )
      end

      it "keeps multibyte text around an edit intact" do
        expect(mutated_patterns("/é+…/")).to eq(["/é…/"])
      end

      it "emits nothing for a pattern regexp_parser cannot read" do
        allow(Evilution::AST::RegexpPattern).to receive(:parse).and_return(nil)

        expect(mutated_patterns("/a+$/")).to be_empty
      end

      it "leaves interpolated patterns alone" do
        expect(mutated_patterns("/\#{s}+/")).to be_empty
      end
    end
  end
end
