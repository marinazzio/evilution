# frozen_string_literal: true

require "evilution/mutator/operator/keyword_argument"

RSpec.describe Evilution::Mutator::Operator::KeywordArgument do
  subject(:operator) { described_class.new }

  let(:registry) { Evilution::Mutator::Registry.new.register(described_class) }

  def mutations_for(source)
    tmpfile = Tempfile.new(["keyword_arg", ".rb"])
    tmpfile.write(source)
    tmpfile.flush

    parser = Evilution::AST::Parser.new
    subjects = parser.call(tmpfile.path)
    subjects.flat_map { |s| registry.mutations_for(s) }
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  describe "removing keyword argument default" do
    it "mutates optional keyword default to required keyword" do
      mutations = mutations_for("def foo(bar: 42)\n  bar\nend\n")

      defaults_removed = mutations.select { |m| m.mutated_source.include?("def foo(bar:)") }
      expect(defaults_removed).not_to be_empty
    end

    it "mutates string default" do
      mutations = mutations_for("def foo(name: \"world\")\n  name\nend\n")

      defaults_removed = mutations.select { |m| m.mutated_source.include?("def foo(name:)") }
      expect(defaults_removed).not_to be_empty
    end

    it "handles multiple keyword arguments" do
      source = "def foo(bar: 1, baz: 2)\n  bar + baz\nend\n"
      mutations = mutations_for(source)

      bar_removed = mutations.select { |m| m.mutated_source.include?("bar:, baz: 2") }
      baz_removed = mutations.select { |m| m.mutated_source.include?("bar: 1, baz:") }
      expect(bar_removed).not_to be_empty
      expect(baz_removed).not_to be_empty
    end

    it "does not mutate required keyword arguments" do
      mutations = mutations_for("def foo(bar:)\n  bar\nend\n")

      keyword_mutations = mutations.select { |m| m.operator_name == "keyword_argument" }
      expect(keyword_mutations).to be_empty
    end
  end

  describe "removing optional keyword parameter" do
    it "removes optional keyword when other params exist" do
      source = "def foo(x, bar: 42)\n  x\nend\n"
      mutations = mutations_for(source)

      removed = mutations.select { |m| m.mutated_source.include?("def foo(x)") }
      expect(removed).not_to be_empty
    end

    it "removes each optional keyword independently" do
      source = "def foo(x, bar: 1, baz: 2)\n  x\nend\n"
      mutations = mutations_for(source)

      bar_removed = mutations.select { |m| m.mutated_source.include?("def foo(x, baz: 2)") }
      baz_removed = mutations.select { |m| m.mutated_source.include?("def foo(x, bar: 1)") }
      expect(bar_removed).not_to be_empty
      expect(baz_removed).not_to be_empty
    end

    it "does not remove required keyword parameters" do
      source = "def foo(x, bar:)\n  x\nend\n"
      mutations = mutations_for(source)

      removed = mutations.select { |m| m.mutated_source.include?("def foo(x)") }
      expect(removed).to be_empty
    end
  end

  describe "removing keyword rest parameter" do
    it "removes **kwargs when other params exist" do
      source = "def foo(x, **opts)\n  x\nend\n"
      mutations = mutations_for(source)

      removed = mutations.select { |m| m.mutated_source.include?("def foo(x)") }
      expect(removed).not_to be_empty
    end

    it "removes standalone **kwargs" do
      source = "def foo(**opts)\n  opts\nend\n"
      mutations = mutations_for(source)

      removed = mutations.select { |m| m.mutated_source.include?("def foo()") || m.mutated_source.include?("def foo") }
      expect(removed).not_to be_empty
    end
  end

  describe "operator name" do
    it "is keyword_argument" do
      expect(described_class.operator_name).to eq("keyword_argument")
    end
  end
end
