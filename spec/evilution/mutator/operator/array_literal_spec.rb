# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/array_literal"

RSpec.describe Evilution::Mutator::Operator::ArrayLiteral do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/array_literal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:non_empty_subject) { subjects.find { |s| s.name.include?("returns_non_empty_array") } }
  let(:empty_subject) { subjects.find { |s| s.name.include?("returns_empty_array") } }

  describe "#call" do
    it "replaces [1, 2, 3] with [] and nil" do
      mutations = described_class.new.call(non_empty_subject)

      expect(mutations.length).to eq(2)
      mutated_sources = mutations.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/\[\]/),
        a_string_matching(/nil/)
      )
    end

    it "does not mutate empty arrays" do
      mutations = described_class.new.call(empty_subject)

      expect(mutations).to be_empty
    end

    # Kills the `node.opening_loc` -> `node` change: an implicit array (the
    # bracket-less RHS of a multiple assignment) has a nil opening_loc and
    # must NOT be mutated; rewriting it would corrupt the assignment.
    it "does not mutate a bracket-less implicit array" do
      src = "class C\n  def m\n    a, b = 1, 2\n  end\nend"
      tmpfile = Tempfile.new(["arrlit", ".rb"])
      tmpfile.write(src)
      tmpfile.flush
      subjects = Evilution::AST::Parser.new.call(tmpfile.path)
      subj = subjects.find { |s| s.name.end_with?("#m") }

      expect(described_class.new.call(subj)).to be_empty
    ensure
      tmpfile&.close
      tmpfile&.unlink
    end

    it "produces valid Ruby for all mutations" do
      subjects.each do |subject|
        mutations = described_class.new.call(subject)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(non_empty_subject)

      expect(mutations.first.operator_name).to eq("array_literal")
    end
  end
end
