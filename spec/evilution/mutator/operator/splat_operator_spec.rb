# frozen_string_literal: true

require "evilution/mutator/operator/splat_operator"

RSpec.describe Evilution::Mutator::Operator::SplatOperator do
  subject(:operator) { described_class.new }

  let(:registry) { Evilution::Mutator::Registry.new.register(described_class) }

  def mutations_for(source)
    tmpfile = Tempfile.new(["splat", ".rb"])
    tmpfile.write(source)
    tmpfile.flush

    parser = Evilution::AST::Parser.new
    subjects = parser.call(tmpfile.path)
    subjects.flat_map { |s| registry.mutations_for(s) }
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  describe "removing splat from method call arguments" do
    it "removes * from *args in a call" do
      mutations = mutations_for("def foo\n  bar(*args)\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("bar(args)") }
      expect(removed).not_to be_empty
    end

    it "removes * from *args with other arguments" do
      mutations = mutations_for("def foo\n  bar(a, *args, b)\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("bar(a, args, b)") }
      expect(removed).not_to be_empty
    end
  end

  describe "removing splat from array literal" do
    it "removes * from [*items]" do
      mutations = mutations_for("def foo\n  [*items]\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("[items]") }
      expect(removed).not_to be_empty
    end

    it "removes * from [a, *rest]" do
      mutations = mutations_for("def foo\n  [a, *rest]\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("[a, rest]") }
      expect(removed).not_to be_empty
    end
  end

  describe "removing double-splat from method call arguments" do
    it "removes ** from **opts in a call" do
      mutations = mutations_for("def foo\n  bar(**opts)\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("bar(opts)") }
      expect(removed).not_to be_empty
    end

    it "removes ** from **opts with other arguments" do
      mutations = mutations_for("def foo\n  bar(x, **opts)\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("bar(x, opts)") }
      expect(removed).not_to be_empty
    end
  end

  describe "edge cases" do
    it "does not mutate double-splat in hash literals" do
      mutations = mutations_for("def foo\n  {**opts}\nend\n")

      splat_mutations = mutations.select { |m| m.operator_name == "splat_operator" }
      expect(splat_mutations).to be_empty
    end

    it "does not mutate double-splat in hash literals with other keys" do
      mutations = mutations_for("def foo\n  {a: 1, **rest}\nend\n")

      splat_mutations = mutations.select { |m| m.operator_name == "splat_operator" }
      expect(splat_mutations).to be_empty
    end

    it "still mutates double-splat in a call nested inside a hash value" do
      mutations = mutations_for("def foo\n  {key: bar(**opts)}\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("bar(opts)") }
      expect(removed).not_to be_empty
    end

    # EV-jjpt (#1202): demoting `**opts` to bare `opts` after an inline kwarg
    # produces `bar(k: v, opts)` — positional-after-keyword, a syntax error.
    # The operator must skip the mutation when a kwarg precedes the splat.
    it "does not mutate double-splat when a kwarg precedes it (positional-after-keyword)" do
      mutations = mutations_for("def foo\n  bar(k: v, **opts)\nend\n")

      splat_mutations = mutations.select { |m| m.operator_name == "splat_operator" }
      expect(splat_mutations).to be_empty
    end

    it "still mutates double-splat when it precedes the kwargs (positional-before-keyword is valid)" do
      mutations = mutations_for("def foo\n  bar(**opts, k: v)\nend\n")

      removed = mutations.select { |m| m.mutated_source.include?("bar(opts, k: v)") }
      expect(removed).not_to be_empty
    end

    it "skips when any kwarg precedes the splat, even with positional args before all of them" do
      mutations = mutations_for("def foo\n  bar(x, k: v, **opts)\nend\n")

      splat_mutations = mutations.select { |m| m.operator_name == "splat_operator" }
      expect(splat_mutations).to be_empty
    end
  end

  describe "valid Ruby output" do
    it "produces valid Ruby for all mutations" do
      sources = [
        "def foo\n  bar(*args)\nend\n",
        "def foo\n  bar(a, *args)\nend\n",
        "def foo\n  [*items]\nend\n",
        "def foo\n  bar(**opts)\nend\n",
        "def foo\n  bar(x, **opts)\nend\n",
        "def foo\n  {**opts}\nend\n",
        "def foo\n  {a: 1, **rest}\nend\n",
        "def foo\n  {key: bar(**opts)}\nend\n"
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

  describe "anonymous splat forwarding" do
    it "does not crash and emits no mutation for an anonymous `*` forward" do
      source = "def foo(*)\n  bar(*)\nend\n"
      expect { mutations_for(source) }.not_to raise_error

      splat_mutations = mutations_for(source).select { |m| m.operator_name == "splat_operator" }
      expect(splat_mutations).to be_empty
    end

    it "does not crash and emits no mutation for an anonymous `**` forward" do
      source = "def foo(**)\n  bar(**)\nend\n"
      expect { mutations_for(source) }.not_to raise_error

      splat_mutations = mutations_for(source).select { |m| m.operator_name == "splat_operator" }
      expect(splat_mutations).to be_empty
    end
  end

  describe "recursion into nested splats" do
    it "mutates a splat nested inside another splat (recurses past the outer splat)" do
      mutations = mutations_for("def foo\n  bar(*[*y])\nend\n")

      sources = mutations.map(&:mutated_source)
      expect(sources).to include("def foo\n  bar([*y])\nend\n")
      expect(sources).to include("def foo\n  bar(*[y])\nend\n")
    end

    it "mutates a splat nested inside a double-splat skipped as a hash element" do
      mutations = mutations_for("def foo\n  {**bar(*x)}\nend\n")

      expect(mutations.map(&:mutated_source)).to include("def foo\n  {**bar(x)}\nend\n")
    end

    it "mutates a splat nested inside a kwarg-preceded double-splat" do
      mutations = mutations_for("def foo\n  bar(k: v, **f(*x))\nend\n")

      expect(mutations.map(&:mutated_source)).to include("def foo\n  bar(k: v, **f(x))\nend\n")
    end
  end

  describe "kwarg-after-splat detection across multiple splats" do
    it "still mutates a later double-splat that is not preceded by any kwarg" do
      mutations = mutations_for("def foo\n  bar(**a, **b)\nend\n")

      sources = mutations.map(&:mutated_source)
      expect(sources).to include("def foo\n  bar(a, **b)\nend\n")
      expect(sources).to include("def foo\n  bar(**a, b)\nend\n")
    end
  end

  describe "operator name" do
    it "is splat_operator" do
      expect(described_class.operator_name).to eq("splat_operator")
    end
  end
end
