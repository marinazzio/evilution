# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/pattern_matching_guard"

RSpec.describe Evilution::Mutator::Operator::PatternMatchingGuard do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/pattern_matching_guard.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  def mutations_for(method_name)
    subject_obj = subjects.find { |s| s.name.include?(method_name) }
    raise "Subject not found: #{method_name}" unless subject_obj

    described_class.new.call(subject_obj)
  end

  describe "#call" do
    it "removes if guard from pattern" do
      mutations = mutations_for("simple_if_guard")

      removed = mutations.select { |m| m.mutated_source.include?("in Integer => n\n") }
      expect(removed).not_to be_empty
    end

    it "negates if guard condition" do
      mutations = mutations_for("simple_if_guard")

      negated = mutations.select { |m| m.mutated_source.include?("if !(n > 0)") }
      expect(negated).not_to be_empty
    end

    it "removes unless guard from pattern" do
      mutations = mutations_for("unless_guard")

      removed = mutations.select { |m| m.mutated_source.include?("in String\n") }
      expect(removed).not_to be_empty
    end

    it "negates unless guard condition" do
      mutations = mutations_for("unless_guard")

      negated = mutations.select { |m| m.mutated_source.include?("unless !(value.empty?)") }
      expect(negated).not_to be_empty
    end

    it "handles complex guard expressions" do
      mutations = mutations_for("complex_guard")

      expect(mutations.length).to eq(2)
      removed = mutations.select { |m| m.mutated_source.include?("in [a, b]\n      :ascending") }
      negated = mutations.select { |m| m.mutated_source.include?("if !(a < b)") }
      expect(removed).not_to be_empty
      expect(negated).not_to be_empty
    end

    it "produces no mutations for patterns without guards" do
      mutations = mutations_for("no_guard")

      expect(mutations).to be_empty
    end

    it "mutates each guarded branch independently" do
      mutations = mutations_for("multiple_guarded_branches")

      expect(mutations.length).to eq(4)
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
      mutations = mutations_for("simple_if_guard")

      expect(mutations.first.operator_name).to eq("pattern_matching_guard")
    end
  end
end
