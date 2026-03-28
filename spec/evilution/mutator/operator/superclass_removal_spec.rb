# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/superclass_removal"

RSpec.describe Evilution::Mutator::Operator::SuperclassRemoval do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/superclass_removal.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:admin_first) { subjects.find { |s| s.name.include?("admin?") } }
  let(:admin_second) { subjects.find { |s| s.name.include?("role") } }
  let(:no_parent_subject) { subjects.find { |s| s.name.include?("no_parent") } }
  let(:namespaced_subject) { subjects.find { |s| s.name.include?("save") } }

  describe "#call" do
    it "generates one mutation for a class with a superclass" do
      mutations = described_class.new.call(admin_first)

      expect(mutations.length).to eq(1)
    end

    it "only generates mutations for the first method in the class" do
      mutations = described_class.new.call(admin_second)

      expect(mutations).to be_empty
    end

    it "generates no mutations for a class without a superclass" do
      mutations = described_class.new.call(no_parent_subject)

      expect(mutations).to be_empty
    end

    it "produces valid Ruby" do
      mutations = described_class.new.call(admin_first)
      mutations.each do |mutation|
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(admin_first)

      expect(mutations.first.operator_name).to eq("superclass_removal")
    end

    it "removes the superclass from the class definition" do
      mutations = described_class.new.call(admin_first)

      expect(mutations.first.diff).to include("- class Admin < User")
      expect(mutations.first.diff).to include("+ class Admin")
    end

    it "handles namespaced superclasses" do
      mutations = described_class.new.call(namespaced_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("- class Service < ActiveRecord::Base")
      expect(mutations.first.diff).to include("+ class Service")
    end
  end
end
