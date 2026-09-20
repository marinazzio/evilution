# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::OptionalDefaultInjection do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/optional_default_injection.rb", __dir__)
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

  # Isolate the mutated method so an expectation reads as the resulting source
  # rather than a byte offset.
  def mutated_bodies(muts, method_name)
    muts.map { |m| m.mutated_source[/  def (?:self\.)?#{method_name}\b.*?\n  end\n/m] }
  end

  def mutations_from_source(inline_source, method_name: nil)
    tmpfile = Tempfile.new(["optional_default_injection", ".rb"])
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
    it "injects the default ahead of the body" do
      muts = mutations_for("single_optional")

      expect(mutated_bodies(muts, "single_optional")).to eq(
        ["  def single_optional(value = 1)\n    value = 1; touch(value)\n  end\n"]
      )
    end

    it "injects ahead of the first of several statements" do
      muts = mutations_for("multi_statement")

      expect(mutated_bodies(muts, "multi_statement")).to eq(
        ["  def multi_statement(value = 1)\n    value = 1; prepare\n    touch(value)\n  end\n"]
      )
    end

    it "emits one mutation per optional parameter, in source order" do
      muts = mutations_for("two_optionals")

      expect(mutated_bodies(muts, "two_optionals")).to eq(
        [
          "  def two_optionals(first = 1, second = 2)\n    first = 1; touch(first, second)\n  end\n",
          "  def two_optionals(first = 1, second = 2)\n    second = 2; touch(first, second)\n  end\n"
        ]
      )
    end

    it "injects a default that is a method call" do
      muts = mutations_for("computed_default")

      expect(mutated_bodies(muts, "computed_default")).to eq(
        ["  def computed_default(value = compute)\n    value = compute; touch(value)\n  end\n"]
      )
    end

    # The default may name an earlier parameter, which is still in scope at the
    # top of the body.
    it "injects a default that reads an earlier parameter" do
      muts = mutations_for("default_from_earlier_parameter")

      expect(mutated_bodies(muts, "default_from_earlier_parameter")).to eq(
        ["  def default_from_earlier_parameter(first, second = first * 2)\n    " \
         "second = first * 2; touch(second)\n  end\n"]
      )
    end

    # A def-level rescue hangs the body off a BeginNode; the injection belongs
    # ahead of the leading statements, not ahead of the whole `def`.
    it "injects ahead of the statements of a body with a rescue clause" do
      muts = mutations_for("with_rescue")

      expect(mutated_bodies(muts, "with_rescue")).to eq(
        ["  def with_rescue(value = 1)\n    value = 1; touch(value)\n  rescue StandardError\n    nil\n  end\n"]
      )
    end

    it "injects ahead of the statements of a body with an ensure clause" do
      muts = mutations_for("with_ensure")

      expect(mutated_bodies(muts, "with_ensure")).to eq(
        ["  def with_ensure(value = 1)\n    value = 1; touch(value)\n  ensure\n    cleanup\n  end\n"]
      )
    end

    # The read is in the rescue clause, but the injection can only go ahead of
    # the leading statements.
    it "injects when the parameter is read only in a rescue clause" do
      muts = mutations_for("read_in_rescue")

      expect(mutated_bodies(muts, "read_in_rescue")).to eq(
        ["  def read_in_rescue(value = 1)\n    value = 1; prepare\n  rescue StandardError\n    " \
         "touch(value)\n  end\n"]
      )
    end

    it "injects when the parameter is read only inside a block" do
      muts = mutations_for("read_inside_block")

      expect(mutated_bodies(muts, "read_inside_block")).to eq(
        ["  def read_inside_block(value = 1)\n    value = 1; [1, 2].each { |i| touch(value, i) }\n  end\n"]
      )
    end

    it "injects into a singleton method" do
      muts = mutations_for("singleton_optional")

      expect(mutated_bodies(muts, "singleton_optional")).to eq(
        ["  def self.singleton_optional(value = 1)\n    value = 1; touch(value)\n  end\n"]
      )
    end

    # Overwriting a value nothing reads changes nothing, so the mutant would
    # survive every suite and report a coverage gap that is not there.
    it "emits nothing when the body never reads the parameter" do
      expect(mutations_for("unused_optional")).to be_empty
    end

    # The block binds its own `value`, so the parameter is never read and
    # overwriting it would change nothing.
    it "emits nothing when the only reads are shadowed by a block parameter" do
      expect(mutations_for("shadowed_by_block_param")).to be_empty
    end

    it "emits nothing for an underscore-prefixed parameter" do
      expect(mutations_for("underscore_optional")).to be_empty
    end

    # The underscore announces a parameter not meant to be read, so it is left
    # alone even where the body does read it.
    it "emits nothing for an underscore-prefixed parameter the body reads" do
      expect(mutations_for("underscore_read")).to be_empty
    end

    # An endless method body holds a single expression; a second statement
    # cannot be put in front of it without changing what the method returns.
    it "emits nothing for an endless method" do
      expect(mutations_for("endless_optional")).to be_empty
    end

    it "emits nothing for an empty body" do
      expect(mutations_for("empty_body")).to be_empty
    end

    it "emits nothing for a body that is only a rescue clause" do
      expect(mutations_for("rescue_only")).to be_empty
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

    it "emits nothing for an optional block parameter" do
      expect(mutations_for("block_with_optional")).to be_empty
    end

    it "mutates a def nested in the body of another" do
      muts = mutations_from_source(
        "def outer\n  def inner(value = 1)\n    touch(value)\n  end\nend\n",
        method_name: "outer"
      )

      expect(muts.map(&:mutated_source)).to eq(
        ["def outer\n  def inner(value = 1)\n    value = 1; touch(value)\n  end\nend\n"]
      )
    end

    it "reports the mutation on the line of the def" do
      muts = mutations_for("single_optional")

      expect(muts.map(&:line)).to eq([5])
    end

    it "names the operator" do
      muts = mutations_for("single_optional")

      expect(muts.map(&:operator_name)).to eq(["optional_default_injection"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("two_optionals") + mutations_for("with_rescue") +
             mutations_for("computed_default") + mutations_for("multi_statement")

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
