# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/pattern_matching_array"

RSpec.describe Evilution::Mutator::Operator::PatternMatchingArray do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/pattern_matching_array.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  def mutations_for(method_name)
    subject_obj = subjects.find { |s| s.name.include?(method_name) }
    raise "Subject not found: #{method_name}" unless subject_obj

    described_class.new.call(subject_obj)
  end

  describe "#call" do
    context "with array patterns" do
      it "removes each element from a multi-element array pattern" do
        mutations = mutations_for("typed_array")

        expect(mutations.map(&:mutated_source)).to include(
          a_string_matching(/in \[String, Symbol\]/),
          a_string_matching(/in \[Integer, Symbol\]/),
          a_string_matching(/in \[Integer, String\]/)
        )
      end

      it "replaces each element with wildcard" do
        mutations = mutations_for("typed_array")

        expect(mutations.map(&:mutated_source)).to include(
          a_string_matching(/in \[_, String, Symbol\]/),
          a_string_matching(/in \[Integer, _, Symbol\]/),
          a_string_matching(/in \[Integer, String, _\]/)
        )
      end

      it "produces 6 mutations for a 3-element array pattern" do
        mutations = mutations_for("typed_array")

        expect(mutations.length).to eq(6)
      end

      it "handles array with rest element" do
        mutations = mutations_for("array_with_rest")

        expect(mutations.length).to eq(4)
        expect(mutations.map(&:mutated_source)).to include(
          a_string_matching(/in \[2, \*rest\]/),
          a_string_matching(/in \[1, \*rest\]/)
        )
      end

      it "handles array with post elements" do
        mutations = mutations_for("array_with_posts")

        expect(mutations.length).to eq(4)
        expect(mutations.map(&:mutated_source)).to include(
          a_string_matching(/in \[\*rest, String\]/),
          a_string_matching(/in \[\*rest, Integer\]/)
        )
      end

      it "only produces wildcard replacement for single-element array" do
        mutations = mutations_for("single_element_array")

        expect(mutations.length).to eq(1)
        expect(mutations.first.mutated_source).to match(/in \[_\]/)
      end
    end

    context "with find patterns" do
      it "replaces required element with wildcard" do
        mutations = mutations_for("find_pattern")

        expect(mutations.length).to eq(1)
        expect(mutations.first.mutated_source).to match(/in \[\*, _, \*\]/)
      end

      it "does not produce removal for single-required find pattern" do
        mutations = mutations_for("find_pattern")

        expect(mutations.length).to eq(1)
      end

      it "removes and wildcards elements in multi-required find pattern" do
        mutations = mutations_for("find_pattern_multiple")

        expect(mutations.length).to eq(4)
      end
    end

    it "produces no mutations for non-array patterns" do
      mutations = mutations_for("no_array_pattern")

      expect(mutations).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      subjects.each do |subject_obj|
        mutations = described_class.new.call(subject_obj)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "Invalid Ruby from #{subject_obj.name}: #{mutation.mutated_source}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = mutations_for("typed_array")

      expect(mutations.first.operator_name).to eq("pattern_matching_array")
    end
  end
end
