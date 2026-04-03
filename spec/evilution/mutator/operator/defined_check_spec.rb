# frozen_string_literal: true

require "evilution/mutator/operator/defined_check"

RSpec.describe Evilution::Mutator::Operator::DefinedCheck do
  subject(:operator) { described_class.new }

  let(:registry) { Evilution::Mutator::Registry.new.register(described_class) }

  def mutations_for(source)
    tmpfile = Tempfile.new(["defined", ".rb"])
    tmpfile.write(source)
    tmpfile.flush

    parser = Evilution::AST::Parser.new
    subjects = parser.call(tmpfile.path)
    subjects.flat_map { |s| registry.mutations_for(s) }
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  describe "replacing defined? with true" do
    it "replaces defined?(foo) with true" do
      mutations = mutations_for("def foo\n  defined?(bar)\nend\n")

      replaced = mutations.select { |m| m.mutated_source.include?("true") && !m.mutated_source.include?("defined?") }
      expect(replaced).not_to be_empty
    end

    it "replaces defined?(@x) with true" do
      mutations = mutations_for("def foo\n  defined?(@x)\nend\n")

      replaced = mutations.select { |m| m.mutated_source.include?("true") && !m.mutated_source.include?("defined?") }
      expect(replaced).not_to be_empty
    end

    it "replaces defined?(Foo::Bar) with true" do
      mutations = mutations_for("def foo\n  defined?(Foo::Bar)\nend\n")

      replaced = mutations.select { |m| m.mutated_source.include?("true") && !m.mutated_source.include?("defined?") }
      expect(replaced).not_to be_empty
    end

    it "replaces defined? used in a conditional" do
      mutations = mutations_for("def foo\n  if defined?(x)\n    x\n  end\nend\n")

      replaced = mutations.select { |m| m.mutated_source.include?("if true") }
      expect(replaced).not_to be_empty
    end
  end

  describe "valid Ruby output" do
    it "produces valid Ruby for all mutations" do
      sources = [
        "def foo\n  defined?(bar)\nend\n",
        "def foo\n  defined?(@x)\nend\n",
        "def foo\n  defined?(Foo::Bar)\nend\n",
        "def foo\n  if defined?(x)\n    x\n  end\nend\n"
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
    it "is defined_check" do
      expect(described_class.operator_name).to eq("defined_check")
    end
  end
end
