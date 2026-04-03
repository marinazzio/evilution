# frozen_string_literal: true

require "evilution/mutator/operator/multiple_assignment"

RSpec.describe Evilution::Mutator::Operator::MultipleAssignment do
  subject(:operator) { described_class.new }

  let(:registry) { Evilution::Mutator::Registry.new.register(described_class) }

  def mutations_for(source)
    tmpfile = Tempfile.new(["masgn", ".rb"])
    tmpfile.write(source)
    tmpfile.flush

    parser = Evilution::AST::Parser.new
    subjects = parser.call(tmpfile.path)
    subjects.flat_map { |s| registry.mutations_for(s) }
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  describe "removing individual assignment targets" do
    it "removes first target" do
      mutations = mutations_for("def foo\n  a, b = 1, 2\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("b = 2") && !m.mutated_source.include?("a,") }
      expect(removed).not_to be_empty
    end

    it "removes second target" do
      mutations = mutations_for("def foo\n  a, b = 1, 2\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("a = 1") && !m.mutated_source.include?(", b") }
      expect(removed).not_to be_empty
    end

    it "removes each target from three-element assignment" do
      mutations = mutations_for("def foo\n  x, y, z = 1, 2, 3\nend\n")

      no_x = mutations.select { |m| m.mutated_source.include?("y, z = 2, 3") }
      no_y = mutations.select { |m| m.mutated_source.include?("x, z = 1, 3") }
      no_z = mutations.select { |m| m.mutated_source.include?("x, y = 1, 2") }
      expect(no_x).not_to be_empty
      expect(no_y).not_to be_empty
      expect(no_z).not_to be_empty
    end
  end

  describe "swapping assignment order" do
    it "swaps two targets" do
      mutations = mutations_for("def foo\n  a, b = 1, 2\nend\n")

      swapped = mutations.select { |m| m.mutated_source.include?("b, a = 1, 2") }
      expect(swapped).not_to be_empty
    end
  end

  describe "edge cases" do
    it "does not mutate when lefts and values count differ" do
      mutations = mutations_for("def foo\n  a, b = [1, 2, 3]\nend\n")

      masgn_mutations = mutations.select { |m| m.operator_name == "multiple_assignment" }
      expect(masgn_mutations).to be_empty
    end

    it "does not mutate splat assignments" do
      mutations = mutations_for("def foo\n  a, *b = 1, 2, 3\nend\n")

      masgn_mutations = mutations.select { |m| m.operator_name == "multiple_assignment" }
      expect(masgn_mutations).to be_empty
    end

    it "does not mutate single assignment" do
      mutations = mutations_for("def foo\n  a = 1\nend\n")

      masgn_mutations = mutations.select { |m| m.operator_name == "multiple_assignment" }
      expect(masgn_mutations).to be_empty
    end
  end

  describe "valid Ruby output" do
    it "produces valid Ruby for all mutations" do
      sources = [
        "def foo\n  a, b = 1, 2\nend\n",
        "def foo\n  x, y, z = 1, 2, 3\nend\n",
        "def foo\n  a, b = foo(), bar()\nend\n"
      ]

      sources.each do |source|
        mutations_for(source).each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "Invalid Ruby produced for #{mutation}: #{result.errors.map(&:message)}"
        end
      end
    end
  end

  describe "operator name" do
    it "is multiple_assignment" do
      expect(described_class.operator_name).to eq("multiple_assignment")
    end
  end
end
