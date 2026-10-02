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

    it "does not remove a lone optional keyword (needs >= 2 params)" do
      mutations = mutations_for("def foo(bar: 42)\n  bar\nend\n")

      empty_params = mutations.select { |m| m.mutated_source.include?("def foo()") }
      expect(empty_params).to be_empty
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

      removed = mutations.reject { |m| m.mutated_source.include?("**opts") }
      expect(removed).not_to be_empty
    end

    it "does not treat a **nil keyword block as a removable keyword rest" do
      source = "def foo(x, **nil)\n  x\nend\n"
      mutations = mutations_for(source)

      keyword_mutations = mutations.select { |m| m.operator_name == "keyword_argument" }
      expect(keyword_mutations).to be_empty
    end

    # An anonymous `**` in a call only parses while the signature declares
    # one, so taking it out of the signature would leave the body unparseable.
    it "keeps an anonymous ** that the body forwards" do
      expect(mutations_for("def foo(*, **, &)\n  bar(*, **, &)\nend\n")).to be_empty
      expect(mutations_for("def foo(x, **)\n  bar(x, **)\nend\n")).to be_empty
      expect(mutations_for("def foo(**)\n  bar(**)\nend\n")).to be_empty
    end

    it "keeps an anonymous ** that the body splats into a hash" do
      expect(mutations_for("def foo(x, **)\n  { x: x, ** }\nend\n")).to be_empty
    end

    it "keeps an anonymous ** forwarded from inside a block" do
      expect(mutations_for("def foo(xs, **)\n  xs.each { |x| bar(x, **) }\nend\n")).to be_empty
    end

    it "removes an anonymous ** that the body does not forward" do
      mutations = mutations_for("def foo(x, **)\n  x\nend\n")

      expect(mutations.map { |m| m.mutated_source.lines.first.strip }).to eq(["def foo(x)"])
    end

    it "removes a standalone anonymous ** that the body does not forward" do
      mutations = mutations_for("def foo(**)\n  1\nend\n")

      expect(mutations.map { |m| m.mutated_source.lines.first.strip }).to eq(["def foo()"])
    end

    it "removes an anonymous ** from an empty method" do
      mutations = mutations_for("def foo(x, **)\nend\n")

      expect(mutations.map { |m| m.mutated_source.lines.first.strip }).to eq(["def foo(x)"])
    end

    # A method defined in the body forwards the anonymous `**` of its own
    # signature, which says nothing about the outer one.
    it "removes an anonymous ** when only a nested def forwards its own" do
      mutations = mutations_for("def foo(x, **)\n  def inner(**) = bar(**)\n  x\nend\n")

      expect(mutations.map { |m| m.mutated_source.lines.first.strip }).to eq(["def foo(x)"])
    end

    # Removing a named rest leaves the body reading an undefined name, which
    # parses and fails at runtime, so the mutant is still worth running.
    it "still removes a named rest that the body forwards" do
      mutations = mutations_for("def foo(x, **opts)\n  bar(x, **opts)\nend\n")

      expect(mutations.map { |m| m.mutated_source.lines.first.strip }).to eq(["def foo(x)"])
    end

    it "keeps optional keyword mutations of a method that forwards an anonymous **" do
      mutations = mutations_for("def foo(strict: true, **)\n  bar(strict: strict, **)\nend\n")

      expect(mutations.map { |m| m.mutated_source.lines.first.strip }).to eq(
        ["def foo(strict:, **)", "def foo(**)"]
      )
      expect(mutations.map(&:parse_status)).to eq(%i[ok ok])
    end
  end

  describe "valid Ruby output" do
    it "produces valid Ruby for all mutations" do
      sources = [
        "def foo(bar: 42)\n  bar\nend\n",
        "def foo(x, bar: 1, baz: 2)\n  x\nend\n",
        "def foo(x, **opts)\n  x\nend\n",
        "def foo(**opts)\n  opts\nend\n"
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
    it "is keyword_argument" do
      expect(described_class.operator_name).to eq("keyword_argument")
    end
  end
end
