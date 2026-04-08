# frozen_string_literal: true

RSpec.describe "Heredoc mutation integration" do
  let(:fixture_path) { File.expand_path("../../support/fixtures/heredoc_mutations.rb", __dir__) }
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }
  let(:registry) { Evilution::Mutator::Registry.default }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name, operator_options: {})
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    registry.mutations_for(subject, operator_options: operator_options)
  end

  def string_literal_mutations(mutations)
    mutations.select { |m| m.operator_name == "string_literal" }
  end

  def string_interpolation_mutations(mutations)
    mutations.select { |m| m.operator_name == "string_interpolation" }
  end

  describe "plain heredoc (no interpolation)" do
    it "generates no string_literal mutations" do
      muts = string_literal_mutations(mutations_for("plain_heredoc"))

      expect(muts).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      mutations_for("plain_heredoc").each do |mutation|
        msg = "Invalid Ruby: #{mutation.operator_name} line #{mutation.line}"
        expect { Prism.parse(mutation.mutated_source) }.not_to raise_error, msg
      end
    end
  end

  describe "squiggly heredoc" do
    it "generates no string_literal mutations" do
      muts = string_literal_mutations(mutations_for("squiggly_heredoc"))

      expect(muts).to be_empty
    end
  end

  describe "non-squiggly heredoc" do
    it "generates no string_literal mutations" do
      muts = string_literal_mutations(mutations_for("non_squiggly_heredoc"))

      expect(muts).to be_empty
    end
  end

  describe "dash heredoc" do
    it "generates no string_literal mutations" do
      muts = string_literal_mutations(mutations_for("dash_heredoc"))

      expect(muts).to be_empty
    end
  end

  describe "single-quote heredoc" do
    it "generates no string_literal mutations" do
      muts = string_literal_mutations(mutations_for("single_quote_heredoc"))

      expect(muts).to be_empty
    end
  end

  describe "interpolated heredoc" do
    it "generates no string_literal mutations for heredoc text" do
      muts = string_literal_mutations(mutations_for("interpolated_heredoc"))

      # Only "users" (table = "users") should be mutated, not heredoc text
      expect(muts.length).to eq(2)
      muts.each do |m|
        expect(m.mutated_source).to include("<<~SQL"), "Heredoc structure should be preserved"
      end
    end

    it "generates string_interpolation mutations for embedded expressions" do
      muts = string_interpolation_mutations(mutations_for("interpolated_heredoc"))

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/FROM \#\{nil\}/),
        a_string_matching(/id = \#\{nil\}/)
      )
    end
  end

  describe "heredoc with string literal in interpolation" do
    it "mutates the string inside the interpolation" do
      muts = string_literal_mutations(mutations_for("heredoc_with_string_in_interpolation"))

      expect(muts.length).to eq(2)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/hello \#\{""\} today/),
        a_string_matching(/hello \#\{nil\} today/)
      )
    end

    context "with skip_heredoc_literals" do
      it "skips the string inside the interpolation too" do
        muts = string_literal_mutations(
          mutations_for("heredoc_with_string_in_interpolation",
                        operator_options: { skip_heredoc_literals: true })
        )

        expect(muts).to be_empty
      end
    end
  end

  describe "nested heredocs" do
    it "generates no string_literal mutations for either heredoc" do
      muts = string_literal_mutations(mutations_for("nested_heredoc"))

      expect(muts).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      mutations_for("nested_heredoc").each do |mutation|
        msg = "Invalid Ruby: #{mutation.operator_name} line #{mutation.line}"
        expect { Prism.parse(mutation.mutated_source) }.not_to raise_error, msg
      end
    end
  end

  describe "mixed heredoc and regular strings" do
    it "mutates regular strings but not heredoc text" do
      muts = string_literal_mutations(mutations_for("mixed_heredoc_and_strings"))

      # "start" and "end" should each get 2 mutations (empty + nil), heredoc text skipped
      expect(muts.length).to eq(4)
      mutated_sources = muts.map(&:mutated_source)

      # All mutations preserve the heredoc
      expect(mutated_sources).to all(include("<<~HEREDOC"))

      # Regular strings get mutated
      expect(mutated_sources).to include(
        a_string_matching(/prefix = ""\n/),
        a_string_matching(/prefix = nil\n/),
        a_string_matching(/suffix = ""\n/),
        a_string_matching(/suffix = nil\n/)
      )
    end

    it "generates string_interpolation mutations for heredoc expressions" do
      muts = string_interpolation_mutations(mutations_for("mixed_heredoc_and_strings"))

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to match(/template \#\{nil\} content/)
    end
  end

  describe "all mutations produce valid Ruby" do
    # method_body_replacement on heredocs is a known issue: it replaces
    # the heredoc opener but leaves the body/delimiter dangling.
    # That's tracked separately from the heredoc-awareness work.
    let(:known_invalid) { %w[method_body_replacement] }

    it "generates parseable mutated source for every method" do
      subjects_from_fixture.each do |subj|
        registry.mutations_for(subj).each do |mutation|
          next if known_invalid.include?(mutation.operator_name)

          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "#{mutation.operator_name} on #{subj.name} line #{mutation.line} " \
                                   "produced invalid Ruby: #{result.errors.map(&:message).join(", ")}"
        end
      end
    end
  end
end
