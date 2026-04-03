# frozen_string_literal: true

require "evilution/mutator/operator/yield_statement"

RSpec.describe Evilution::Mutator::Operator::YieldStatement do
  subject(:operator) { described_class.new }

  let(:registry) { Evilution::Mutator::Registry.new.register(described_class) }

  def mutations_for(source)
    tmpfile = Tempfile.new(["yield", ".rb"])
    tmpfile.write(source)
    tmpfile.flush

    parser = Evilution::AST::Parser.new
    subjects = parser.call(tmpfile.path)
    subjects.flat_map { |s| registry.mutations_for(s) }
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  describe "remove yield entirely" do
    it "replaces yield with nil" do
      mutations = mutations_for("def foo\n  yield\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("nil") && !m.mutated_source.include?("yield") }
      expect(removed).not_to be_empty
    end

    it "replaces yield with arguments with nil" do
      mutations = mutations_for("def foo\n  yield(x, y)\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("def foo\n  nil\nend") }
      expect(removed).not_to be_empty
    end
  end

  describe "remove yield arguments" do
    it "removes arguments from yield(x, y)" do
      mutations = mutations_for("def foo\n  yield(x, y)\nend\n")

      no_args = mutations.select { |m| m.mutated_source.include?("yield") && !m.mutated_source.include?("yield(") }
      expect(no_args).not_to be_empty
    end

    it "removes argument from yield(x)" do
      mutations = mutations_for("def foo\n  yield(x)\nend\n")

      no_args = mutations.select { |m| m.mutated_source.include?("yield") && !m.mutated_source.include?("yield(") }
      expect(no_args).not_to be_empty
    end

    it "removes arguments from yield without parens" do
      mutations = mutations_for("def foo\n  yield x, y\nend\n")

      no_args = mutations.select { |m| m.mutated_source.include?("yield\n") }
      expect(no_args).not_to be_empty
    end

    it "does not produce remove-arguments mutation for bare yield" do
      mutations = mutations_for("def foo\n  yield\nend\n")

      yield_mutations = mutations.select { |m| m.operator_name == "yield_statement" }
      # bare yield should only have "remove yield" mutation, not "remove arguments"
      expect(yield_mutations.length).to eq(1)
    end
  end

  describe "replace yield value with nil" do
    it "replaces yield(x) with yield(nil)" do
      mutations = mutations_for("def foo\n  yield(x)\nend\n")

      nil_arg = mutations.select { |m| m.mutated_source.include?("yield(nil)") }
      expect(nil_arg).not_to be_empty
    end

    it "replaces yield(x, y) with yield(nil)" do
      mutations = mutations_for("def foo\n  yield(x, y)\nend\n")

      nil_arg = mutations.select { |m| m.mutated_source.include?("yield(nil)") }
      expect(nil_arg).not_to be_empty
    end

    it "replaces yield x with yield nil for no-paren form" do
      mutations = mutations_for("def foo\n  yield x\nend\n")

      nil_arg = mutations.select { |m| m.mutated_source.include?("yield nil") }
      expect(nil_arg).not_to be_empty
    end

    it "does not produce replace-with-nil for bare yield" do
      mutations = mutations_for("def foo\n  yield\nend\n")

      nil_mutations = mutations.select { |m| m.mutated_source.include?("yield(nil)") || m.mutated_source.include?("yield nil") }
      expect(nil_mutations).to be_empty
    end
  end

  describe "valid Ruby output" do
    it "produces valid Ruby for all mutations" do
      sources = [
        "def foo\n  yield\nend\n",
        "def foo\n  yield(x)\nend\n",
        "def foo\n  yield(x, y)\nend\n",
        "def foo\n  yield x\nend\n",
        "def foo\n  yield x, y\nend\n",
        "def foo(&blk)\n  yield(1, 2, 3)\nend\n"
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
    it "is yield_statement" do
      expect(described_class.operator_name).to eq("yield_statement")
    end
  end
end
