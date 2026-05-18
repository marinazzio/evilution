# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/global_variable_write"

RSpec.describe Evilution::Mutator::Operator::GlobalVariableWrite do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/global_variable_write.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:multi_subject) { subjects.find { |s| s.name.include?("with_gvars") } }
  let(:single_subject) { subjects.find { |s| s.name.include?("single_gvar") } }
  let(:no_gvar_subject) { subjects.find { |s| s.name.include?("no_gvars") } }

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["global_variable_write", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "generates two mutations per global variable write" do
      mutations = described_class.new.call(multi_subject)

      expect(mutations.length).to eq(4)
    end

    it "generates two mutations for a single gvar write" do
      mutations = described_class.new.call(single_subject)

      expect(mutations.length).to eq(2)
    end

    it "generates no mutations when there are no gvar writes" do
      mutations = described_class.new.call(no_gvar_subject)

      expect(mutations).to be_empty
    end

    it "recurses into a nested global variable write so the inner write is also mutated" do
      mutations = mutations_from_source("def m\n  $a = ($b = 1)\n  $a\nend\n")

      # 2 mutations for the outer $a write + 2 for the nested $b write
      expect(mutations.length).to eq(4)
    end

    it "generates a removal mutation that keeps only the value" do
      mutations = described_class.new.call(single_subject)
      removal = mutations.find { |m| m.diff.include?("compute") && !m.diff.include?("nil") }

      expect(removal).not_to be_nil
      expect(removal.diff).to include("- ", "$output = compute")
      expect(removal.diff).to include("+ ", "compute")
    end

    it "generates a nil replacement mutation" do
      mutations = described_class.new.call(single_subject)
      nil_mutation = mutations.find { |m| m.diff.include?("nil") }

      expect(nil_mutation).not_to be_nil
      expect(nil_mutation.diff).to include("- ", "$output = compute")
      expect(nil_mutation.diff).to include("+ ", "$output = nil")
    end

    it "produces valid Ruby for all mutations" do
      mutations = described_class.new.call(multi_subject)
      mutations.each do |mutation|
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(multi_subject)

      expect(mutations.first.operator_name).to eq("global_variable_write")
    end
  end
end
