# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/mixin_removal"

RSpec.describe Evilution::Mutator::Operator::MixinRemoval do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/mixin_removal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:first_method_subject) { subjects.find { |s| s.name.include?("first_method") } }
  let(:second_method_subject) { subjects.find { |s| s.name.include?("second_method") } }
  let(:no_mixin_subject) { subjects.find { |s| s.name.include?("plain_method") } }
  let(:multiple_mixin_subject) { subjects.find { |s| s.name.include?("with_multiple") } }

  describe "#call" do
    it "generates one mutation per mixin statement" do
      mutations = described_class.new.call(first_method_subject)

      expect(mutations.length).to eq(3)
    end

    it "only generates mutations for the first method in the class" do
      mutations = described_class.new.call(second_method_subject)

      expect(mutations).to be_empty
    end

    it "generates no mutations for a class without mixins" do
      mutations = described_class.new.call(no_mixin_subject)

      expect(mutations).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      mutations = described_class.new.call(first_method_subject)
      mutations.each do |mutation|
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(first_method_subject)

      expect(mutations.first.operator_name).to eq("mixin_removal")
    end

    it "removes the include statement" do
      mutations = described_class.new.call(first_method_subject)
      diffs = mutations.map(&:diff)

      expect(diffs).to include(a_string_including("- ", "include Comparable"))
    end

    it "removes the extend statement" do
      mutations = described_class.new.call(first_method_subject)
      diffs = mutations.map(&:diff)

      expect(diffs).to include(a_string_including("- ", "extend ClassMethods"))
    end

    it "removes the prepend statement" do
      mutations = described_class.new.call(first_method_subject)
      diffs = mutations.map(&:diff)

      expect(diffs).to include(a_string_including("- ", "prepend Logging"))
    end

    it "handles classes with multiple include statements" do
      mutations = described_class.new.call(multiple_mixin_subject)

      expect(mutations.length).to eq(2)
    end
  end
end
