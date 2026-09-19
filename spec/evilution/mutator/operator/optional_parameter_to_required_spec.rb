# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::OptionalParameterToRequired do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/optional_parameter_to_required.rb", __dir__)
  end
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def subject_for(method_name)
    subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}", ".#{method_name}") }
  end

  def mutations_for(method_name)
    described_class.new.call(subject_for(method_name))
  end

  # The signature line alone reads better in an expectation than a byte offset.
  def mutated_signatures(muts, method_name)
    muts.map { |m| m.mutated_source[/  def (?:self\.)?#{method_name}\b[^\n]*/] }
  end

  def mutations_from_source(inline_source, method_name: nil)
    tmpfile = Tempfile.new(["optional_parameter_to_required", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects = subjects.select { |s| s.name.end_with?("##{method_name}", ".#{method_name}") } if method_name
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "drops the default of a lone optional parameter" do
      muts = mutations_for("single_optional")

      expect(mutated_signatures(muts, "single_optional")).to eq(["  def single_optional(value)"])
    end

    it "keeps a preceding required parameter" do
      muts = mutations_for("leading_required")

      expect(mutated_signatures(muts, "leading_required")).to eq(["  def leading_required(first, value)"])
    end

    # Ruby allows a required parameter after an optional one, so each optional
    # can be made required on its own. They are emitted in source order, which
    # is the order the reporter lists them in.
    it "emits one mutation per optional parameter, in source order" do
      muts = mutations_for("two_optionals")

      expect(mutated_signatures(muts, "two_optionals")).to eq(
        [
          "  def two_optionals(first, second = 2)",
          "  def two_optionals(first = 1, second)"
        ]
      )
    end

    it "keeps a following rest parameter" do
      muts = mutations_for("with_rest")

      expect(mutated_signatures(muts, "with_rest")).to eq(["  def with_rest(value, *rest)"])
    end

    it "keeps a following keyword parameter" do
      muts = mutations_for("with_keyword")

      expect(mutated_signatures(muts, "with_keyword")).to eq(["  def with_keyword(value, key: nil)"])
    end

    it "keeps a following block parameter" do
      muts = mutations_for("with_block")

      expect(mutated_signatures(muts, "with_block")).to eq(["  def with_block(value, &blk)"])
    end

    it "drops a default that is a method call" do
      muts = mutations_for("complex_default")

      expect(mutated_signatures(muts, "complex_default")).to eq(["  def complex_default(value)"])
    end

    it "mutates an endless method signature" do
      muts = mutations_for("endless_optional")

      expect(mutated_signatures(muts, "endless_optional")).to eq(["  def endless_optional(value) = value"])
    end

    it "mutates a singleton method signature" do
      muts = mutations_for("singleton_optional")

      expect(mutated_signatures(muts, "singleton_optional")).to eq(["  def self.singleton_optional(value)"])
    end

    it "emits nothing for a required parameter" do
      expect(mutations_for("only_required")).to be_empty
    end

    # KeywordArgument owns optional keyword parameters.
    it "emits nothing for an optional keyword parameter" do
      expect(mutations_for("only_keyword")).to be_empty
    end

    it "emits nothing for a method without parameters" do
      expect(mutations_for("no_params")).to be_empty
    end

    # A block ignores arity, so a missing argument arrives as nil instead of
    # raising: making its parameter required changes nothing.
    it "emits nothing for an optional block parameter" do
      expect(mutations_for("block_with_optional")).to be_empty
    end

    it "emits nothing for an optional lambda parameter" do
      expect(mutations_for("lambda_with_optional")).to be_empty
    end

    # The same mutation is reached again through the inner subject and
    # deduplicated by the runner, not here, so the outer subject is asked alone.
    it "mutates a def nested in the body of another" do
      muts = mutations_from_source(
        "def outer\n  def inner(value = 1)\n    value\n  end\nend\n",
        method_name: "outer"
      )

      expect(muts.map(&:mutated_source)).to eq(
        ["def outer\n  def inner(value)\n    value\n  end\nend\n"]
      )
    end

    it "reports the mutation on the line of the def" do
      muts = mutations_for("single_optional")

      expect(muts.map(&:line)).to eq([5])
    end

    it "names the operator" do
      muts = mutations_for("single_optional")

      expect(muts.map(&:operator_name)).to eq(["optional_parameter_to_required"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("two_optionals") + mutations_for("with_rest") +
             mutations_for("endless_optional") + mutations_for("with_block")

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["optional_parameter"])

      muts = described_class.new.call(subject_for("single_optional"), filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
