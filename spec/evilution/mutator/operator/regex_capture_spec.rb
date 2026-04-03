# frozen_string_literal: true

require "evilution/mutator/operator/regex_capture"

RSpec.describe Evilution::Mutator::Operator::RegexCapture do
  subject(:operator) { described_class.new }

  let(:registry) { Evilution::Mutator::Registry.new.register(described_class) }

  def mutations_for(source)
    tmpfile = Tempfile.new(["regex_capture", ".rb"])
    tmpfile.write(source)
    tmpfile.flush

    parser = Evilution::AST::Parser.new
    subjects = parser.call(tmpfile.path)
    subjects.flat_map { |s| registry.mutations_for(s) }
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  describe "replacing with nil" do
    it "replaces $1 with nil" do
      mutations = mutations_for("def foo\n  $1\nend\n")

      replaced = mutations.select { |m| m.mutated_source.include?("nil") && !m.mutated_source.include?("$1") }
      expect(replaced).not_to be_empty
    end

    it "replaces $2 with nil" do
      mutations = mutations_for("def foo\n  $2\nend\n")

      replaced = mutations.select { |m| m.mutated_source.include?("nil") && !m.mutated_source.include?("$2") }
      expect(replaced).not_to be_empty
    end
  end

  describe "swapping capture numbers" do
    it "swaps $1 to $2" do
      mutations = mutations_for("def foo\n  $1\nend\n")

      swapped = mutations.select { |m| m.mutated_source.include?("$2") }
      expect(swapped).not_to be_empty
    end

    it "swaps $2 to $1 and $3" do
      mutations = mutations_for("def foo\n  $2\nend\n")

      decremented = mutations.select { |m| m.mutated_source.include?("$1") }
      incremented = mutations.select { |m| m.mutated_source.include?("$3") }
      expect(decremented).not_to be_empty
      expect(incremented).not_to be_empty
    end

    it "does not swap $1 to $0" do
      mutations = mutations_for("def foo\n  $1\nend\n")

      zero_ref = mutations.select { |m| m.mutated_source.include?("$0") }
      expect(zero_ref).to be_empty
    end
  end

  describe "valid Ruby output" do
    it "produces valid Ruby for all mutations" do
      sources = [
        "def foo\n  $1\nend\n",
        "def foo\n  $2\nend\n",
        "def foo\n  $10\nend\n"
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
    it "is regex_capture" do
      expect(described_class.operator_name).to eq("regex_capture")
    end
  end
end
