# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/rescue_removal"

RSpec.describe Evilution::Mutator::Operator::RescueRemoval do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/rescue_removal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:single_subject) { subjects.find { |s| s.name.include?("single_rescue") } }
  let(:multi_subject) { subjects.find { |s| s.name.include?("multiple_rescues") } }
  let(:no_rescue_subject) { subjects.find { |s| s.name.include?("no_rescue") } }
  let(:body_subject) { subjects.find { |s| s.name.include?("rescue_with_body") } }

  describe "#call" do
    it "generates one mutation for a single rescue clause" do
      mutations = described_class.new.call(single_subject)

      expect(mutations.length).to eq(1)
    end

    it "generates one mutation per rescue clause for multiple rescues" do
      mutations = described_class.new.call(multi_subject)

      expect(mutations.length).to eq(2)
    end

    it "generates no mutations when there is no rescue" do
      mutations = described_class.new.call(no_rescue_subject)

      expect(mutations).to be_empty
    end

    it "removes the single rescue clause entirely" do
      mutations = described_class.new.call(single_subject)
      mutation = mutations.first

      expect(mutation.diff).to include("- ", "rescue ArgumentError")
      expect(mutation.diff).to include("- ", "handle_error")
      result = Prism.parse(mutation.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
    end

    it "removes the first rescue clause from multiple rescues" do
      mutations = described_class.new.call(multi_subject)
      first_removal = mutations.find { |m| m.diff.include?("ArgumentError") }

      expect(first_removal).not_to be_nil
      expect(first_removal.diff).to include("rescue ArgumentError")
      expect(first_removal.diff).not_to include("RuntimeError")
      result = Prism.parse(first_removal.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{first_removal.mutated_source}"
    end

    it "removes the second rescue clause from multiple rescues" do
      mutations = described_class.new.call(multi_subject)
      second_removal = mutations.find { |m| m.diff.include?("RuntimeError") }

      expect(second_removal).not_to be_nil
      expect(second_removal.diff).to include("rescue RuntimeError")
      expect(second_removal.diff).not_to include("ArgumentError")
      result = Prism.parse(second_removal.mutated_source)
      expect(result.errors).to be_empty, "Invalid Ruby: #{second_removal.mutated_source}"
    end

    it "produces valid Ruby for all mutations" do
      mutations = described_class.new.call(body_subject)
      mutations.each do |mutation|
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(single_subject)

      expect(mutations.first.operator_name).to eq("rescue_removal")
    end

    describe "orphan-clause safety" do
      let(:else_subject) { subjects.find { |s| s.name.include?("rescue_with_else") } }
      let(:else_ensure_subject) do
        subjects.find { |s| s.name.include?("rescue_with_else_and_ensure") }
      end
      let(:multi_else_subject) do
        subjects.find { |s| s.name.include?("multiple_rescues_with_else") }
      end
      let(:comment_only_subject) do
        subjects.find { |s| s.name.include?("rescue_comment_only_with_ensure") }
      end

      it "removes the trailing else when stripping the sole rescue clause" do
        mutations = described_class.new.call(else_subject)

        expect(mutations.length).to eq(1)
        mutation = mutations.first
        expect(mutation.parse_status).to eq(:ok)
        # else clause must NOT remain in the mutated source — it would orphan.
        plus_lines = mutation.diff.lines.select { |l| l.start_with?("+") }.join
        expect(plus_lines).not_to match(/^\+\s*else\b/)
        expect(plus_lines).not_to include("succeed")
      end

      it "removes the trailing else but keeps ensure when stripping the sole rescue (begin/rescue/else/ensure)" do
        mutations = described_class.new.call(else_ensure_subject)

        expect(mutations.length).to eq(1)
        mutation = mutations.first
        expect(mutation.parse_status).to eq(:ok)
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty,
                                 "Invalid Ruby: #{mutation.mutated_source}"
        # ensure must remain; else must go.
        expect(mutation.mutated_source).to include("ensure")
        expect(mutation.mutated_source).to include("cleanup")
      end

      it "keeps else valid when one of multiple rescues is removed" do
        mutations = described_class.new.call(multi_else_subject)

        # Both mutations must parse — else stays because another rescue
        # remains in the chain.
        expect(mutations.length).to eq(2)
        mutations.each do |mutation|
          expect(mutation.parse_status).to eq(:ok)
          # else and its body are still present
          expect(mutation.mutated_source).to include("else")
          expect(mutation.mutated_source).to include("succeed")
        end
      end

      it "removes the full rescue clause when the rescue body is comment-only" do
        # roda streaming.rb / sinatra base.rb variant: body has no statements,
        # so the operator must use clause boundaries (next clause / end) — NOT
        # the keyword location — to compute the removal end.
        mutations = described_class.new.call(comment_only_subject)

        expect(mutations.length).to eq(1)
        mutation = mutations.first
        expect(mutation.parse_status).to eq(:ok)
        # The `+` lines must not contain any leftover rescue tokens. Both the
        # `rescue` keyword and the exception class name should be removed
        # together — no orphaned `end ClosedQueueError`.
        plus_lines = mutation.diff.lines.select { |l| l.start_with?("+") }.join
        expect(plus_lines).not_to include("rescue")
        expect(plus_lines).not_to include("ClosedQueueError")
        # The ensure block still runs in the surviving body.
        expect(mutation.mutated_source).to include("ensure")
        expect(mutation.mutated_source).to include("cleanup")
      end
    end
  end
end
