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
  end
end
