# frozen_string_literal: true

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
  end
end
