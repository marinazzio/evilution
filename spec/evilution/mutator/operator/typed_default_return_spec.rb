# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::TypedDefaultReturn do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/typed_default_return.rb", __dir__) }
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
    tmpfile = Tempfile.new(["typed_default_return", ".rb"])
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
    it "replaces a body returning a mapped collection with an empty array" do
      muts = mutations_for("mapped")

      expect(mutated_bodies(muts, "mapped")).to eq(
        ["  def mapped(users)\n    []\n  end\n"]
      )
    end

    it "replaces a body returning a filtered collection with an empty array" do
      muts = mutations_for("selected")

      expect(mutated_bodies(muts, "selected")).to eq(
        ["  def selected(users)\n    []\n  end\n"]
      )
    end

    it "replaces a body returning a hash with an empty hash" do
      muts = mutations_for("hashed")

      expect(mutated_bodies(muts, "hashed")).to eq(
        ["  def hashed(users)\n    {}\n  end\n"]
      )
    end

    it "replaces a body returning a count with zero" do
      muts = mutations_for("counted")

      expect(mutated_bodies(muts, "counted")).to eq(
        ["  def counted(users)\n    0\n  end\n"]
      )
    end

    # The type comes from the outermost call, which is what the method returns.
    it "replaces a chained body from its trailing selector" do
      muts = mutations_for("joined")

      expect(mutated_bodies(muts, "joined")).to eq(
        ["  def joined(users)\n    \"\"\n  end\n"]
      )
    end

    it "replaces an interpolated string body with an empty string" do
      muts = mutations_for("interpolated")

      expect(mutated_bodies(muts, "interpolated")).to eq(
        ["  def interpolated(name)\n    \"\"\n  end\n"]
      )
    end

    it "replaces the body of an endless method" do
      muts = mutations_for("endless_mapped")

      expect(muts.map { |m| m.mutated_source[/  def endless_mapped.*$/] }).to eq(
        ["  def endless_mapped(users) = []"]
      )
    end

    # A def-level rescue hangs the body off a BeginNode whose span covers the
    # whole `def...end`; only the leading statements may be replaced.
    it "replaces only the statements of a body with a rescue clause" do
      muts = mutations_for("with_rescue")

      expect(mutated_bodies(muts, "with_rescue")).to eq(
        ["  def with_rescue(users)\n    []\n  rescue StandardError\n    []\n  end\n"]
      )
    end

    it "mutates a body reached through a safe navigation call" do
      muts = mutations_from_source("def listed(users)\n  users&.map(&:name)\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def listed(users)\n  []\nend\n"])
    end

    # The literal operators (array_literal, hash_literal, string_literal,
    # integer_literal, float_literal) already emit the empty value for these.
    it "emits nothing for a literal array body" do
      expect(mutations_for("literal_array")).to be_empty
    end

    it "emits nothing for a literal hash body" do
      expect(mutations_for("literal_hash")).to be_empty
    end

    it "emits nothing for a literal string body" do
      expect(mutations_for("literal_string")).to be_empty
    end

    it "emits nothing for a literal integer body" do
      expect(mutations_for("literal_integer")).to be_empty
    end

    it "emits nothing for a literal float body" do
      expect(mutations_for("literal_float")).to be_empty
    end

    it "emits nothing when the trailing selector is not in the table" do
      expect(mutations_for("unknown_selector")).to be_empty
    end

    it "emits nothing for a body that is not a call" do
      expect(mutations_for("instance_variable_body")).to be_empty
    end

    # CollectionReturn and ScalarReturn own bodies of two or more statements.
    it "emits nothing for a multi-statement body" do
      expect(mutations_for("multi_statement")).to be_empty
    end

    # The guard is on the statement count, not on where a qualifying call sits:
    # here the leading statement would match but the method returns something
    # else entirely.
    it "emits nothing for a multi-statement body whose first statement is a qualifying call" do
      expect(mutations_for("multi_statement_leading_call")).to be_empty
    end

    # Visiting a subject descends into a def nested in its body. The enclosing
    # body here is that nested def, which has no default of its own, so the one
    # mutation comes from the inner method.
    it "mutates a def nested in the body of another" do
      muts = mutations_from_source(
        "def outer(users)\n  def inner(users)\n    users.count\n  end\nend\n",
        method_name: "outer"
      )

      expect(muts.map(&:mutated_source)).to eq(
        ["def outer(users)\n  def inner(users)\n    0\n  end\nend\n"]
      )
    end

    it "emits nothing for an empty method body" do
      expect(mutations_for("empty_method")).to be_empty
    end

    it "emits nothing for a body that is only a rescue clause" do
      expect(mutations_for("rescue_only")).to be_empty
    end

    it "reports the mutation on the line of the def" do
      muts = mutations_for("mapped")

      expect(muts.map(&:line)).to eq([5])
    end

    it "names the operator" do
      muts = mutations_for("mapped")

      expect(muts.map(&:operator_name)).to eq(["typed_default_return"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("mapped") + mutations_for("endless_mapped") +
             mutations_for("with_rescue") + mutations_for("interpolated")

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["def"])

      muts = described_class.new.call(subject_for("mapped"), filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
