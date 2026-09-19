# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BlockParameterDrop do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/block_parameter_drop.rb", __dir__) }
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
    muts.map { |m| m.mutated_source[/  def #{method_name}\b.*?\n  end\n/m] }
  end

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["block_parameter_drop", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "drops the parameter of a brace block" do
      muts = mutations_for("single_param")

      expect(mutated_bodies(muts, "single_param")).to eq(
        ["  def single_param(users)\n    users.each { touch(u) }\n  end\n"]
      )
    end

    it "drops the parameter of a do/end block" do
      muts = mutations_for("do_end")

      expect(mutated_bodies(muts, "do_end")).to eq(
        ["  def do_end(users)\n    users.each do\n      touch(u)\n    end\n  end\n"]
      )
    end

    it "drops a destructured single parameter" do
      muts = mutations_for("destructured")

      expect(mutated_bodies(muts, "destructured")).to eq(
        ["  def destructured(pairs)\n    pairs.each { touch(key, value) }\n  end\n"]
      )
    end

    it "mutates each block of a nested pair" do
      muts = mutations_for("nested")

      expect(mutated_bodies(muts, "nested")).to contain_exactly(
        "  def nested(users)\n    users.each { u.tags.each { |t| touch(t) } }\n  end\n",
        "  def nested(users)\n    users.each { |u| u.tags.each { touch(t) } }\n  end\n"
      )
    end

    # The outer parameter is used only inside the inner block, which shares the
    # enclosing scope, so it is still a reference.
    it "drops an outer parameter referenced only inside a nested block" do
      muts = mutations_for("referenced_in_nested_block")

      expect(mutated_bodies(muts, "referenced_in_nested_block")).to include(
        "  def referenced_in_nested_block(users)\n    users.each { u.tags.each { |t| touch(u, t) } }\n  end\n"
      )
    end

    # Dropping a parameter the body never reads changes nothing, so the mutant
    # would survive every suite and report a coverage gap that is not there.
    it "emits nothing when the body never references the parameter" do
      expect(mutations_for("unused_param")).to be_empty
    end

    it "emits nothing for an underscore-prefixed parameter" do
      expect(mutations_for("underscore_param")).to be_empty
    end

    # any?, not all?: the mutation is worth emitting as soon as one of the
    # destructured names is read.
    it "drops a destructured parameter when only one of its names is read" do
      muts = mutations_for("destructured_partial")

      expect(mutated_bodies(muts, "destructured_partial")).to eq(
        ["  def destructured_partial(pairs)\n    pairs.each { touch(key) }\n  end\n"]
      )
    end

    it "keeps the brace spacing when no space precedes the parameters" do
      muts = mutations_for("no_space_before_params")

      expect(mutated_bodies(muts, "no_space_before_params")).to eq(
        ["  def no_space_before_params(users)\n    users.each { touch(u) }\n  end\n"]
      )
    end

    it "emits nothing for a block with an empty body" do
      expect(mutations_for("empty_block")).to be_empty
    end

    it "emits nothing for a block with empty parameter pipes" do
      expect(mutations_for("empty_pipes")).to be_empty
    end

    it "emits nothing for an underscore-prefixed parameter the body reads" do
      expect(mutations_for("underscore_referenced")).to be_empty
    end

    # The body reads a local, but not the parameter's own name.
    it "emits nothing when the body reads a different local" do
      expect(mutations_for("other_local_read")).to be_empty
    end

    # A nested def opens its own scope, so a local of the same name declared in
    # there is not a read of the block parameter.
    it "emits nothing when only a nested def declares a local of the same name" do
      expect(mutations_for("local_in_nested_def")).to be_empty
    end

    # The scan skips a nested def and keeps going: the read after it still
    # counts.
    it "drops a parameter read after a nested def in the same block" do
      muts = mutations_for("nested_def_before_read")

      expect(mutated_bodies(muts, "nested_def_before_read")).to eq(
        ["  def nested_def_before_read(users)\n    users.each do\n      def helper\n        1\n      " \
         "end\n      touch(u)\n    end\n  end\n"]
      )
    end

    it "emits nothing for a splat parameter" do
      expect(mutations_for("splat_param")).to be_empty
    end

    it "emits nothing for a block with a keyword parameter" do
      expect(mutations_for("keyword_param")).to be_empty
    end

    it "emits nothing for a block with a keyword rest parameter" do
      expect(mutations_for("keyword_rest_param")).to be_empty
    end

    it "emits nothing for a block with a block-pass parameter" do
      expect(mutations_for("block_pass_param")).to be_empty
    end

    it "emits nothing for a block with two parameters" do
      expect(mutations_for("two_params")).to be_empty
    end

    # `|key,|` already disables procarg0; Prism reports the trailing comma as an
    # implicit rest parameter, so this is not a single-parameter block.
    it "emits nothing for a parameter with a trailing comma" do
      expect(mutations_for("trailing_comma")).to be_empty
    end

    it "emits nothing for a block declaring block-local variables" do
      expect(mutations_for("block_locals")).to be_empty
    end

    it "emits nothing for a block using numbered parameters" do
      expect(mutations_for("numbered_param")).to be_empty
    end

    it "emits nothing for a block without parameters" do
      expect(mutations_for("no_params")).to be_empty
    end

    it "emits nothing for a block with an optional parameter" do
      expect(mutations_for("optional_param")).to be_empty
    end

    # A lambda checks its arity, so dropping the parameter raises ArgumentError
    # on every call regardless of what the body does.
    it "emits nothing for a lambda literal" do
      expect(mutations_for("lambda_literal")).to be_empty
    end

    it "emits nothing for a block whose only parameter is a block pass" do
      expect(mutations_from_source("def call(items)\n  items.each { |&blk| blk.call }\nend\n")).to be_empty
    end

    it "reports the mutation on the line of the block" do
      muts = mutations_for("single_param")

      expect(muts.map(&:line)).to eq([6])
    end

    it "names the operator" do
      muts = mutations_for("single_param")

      expect(muts.map(&:operator_name)).to eq(["block_parameter_drop"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("single_param") + mutations_for("do_end") + mutations_for("destructured")

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["block"])

      muts = described_class.new.call(subject_for("single_param"), filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
