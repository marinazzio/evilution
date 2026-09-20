# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BlockDestructuringExpansion do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/block_destructuring_expansion.rb", __dir__)
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

  # The mutated method's own parameter list reads better in an expectation than
  # a byte offset. Scoped to the method, since the fixture is full of blocks.
  def mutated_parameters(muts, method_name)
    muts.map { |m| m.mutated_source[/def #{method_name}\b.*?(\|[^|]*\|)/m, 1] }
  end

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["block_destructuring_expansion", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "flattens a group followed by a sibling parameter" do
      muts = mutations_for("group_then_sibling")

      expect(mutated_parameters(muts, "group_then_sibling")).to eq(["|key, value, index|"])
    end

    it "flattens a group preceded by a sibling parameter" do
      muts = mutations_for("sibling_then_group")

      expect(mutated_parameters(muts, "sibling_then_group")).to eq(["|index, key, value|"])
    end

    it "flattens a group in a do/end block" do
      muts = mutations_for("do_end_form")

      expect(mutated_parameters(muts, "do_end_form")).to eq(["|key, value, index|"])
    end

    it "flattens a group beside a splat parameter" do
      muts = mutations_for("group_with_splat_sibling")

      expect(mutated_parameters(muts, "group_with_splat_sibling")).to eq(["|key, value, *rest|"])
    end

    it "keeps a splat inside the group" do
      muts = mutations_for("splat_inside_group")

      expect(mutated_parameters(muts, "splat_inside_group")).to eq(["|key, *rest, index|"])
    end

    # Only the outer group is flattened; the inner one still destructures.
    it "flattens the outer level of a nested group" do
      muts = mutations_for("nested_group")

      expect(mutated_parameters(muts, "nested_group")).to eq(["|(first, second), third, index|"])
    end

    it "emits one mutation per group, in source order" do
      muts = mutations_for("two_groups")

      expect(mutated_parameters(muts, "two_groups")).to eq(
        [
          "|first, second, (third, fourth)|",
          "|(first, second), third, fourth|"
        ]
      )
    end

    # `|*rest, (a, b)|` puts the group in the post-required list rather than
    # the required one.
    it "flattens a group that follows a splat parameter" do
      muts = mutations_for("group_in_posts")

      expect(mutated_parameters(muts, "group_in_posts")).to eq(["|*rest, key, value|"])
    end

    it "flattens a group in a signature using every parameter kind" do
      muts = mutations_for("every_parameter_kind")

      expect(mutated_parameters(muts, "every_parameter_kind")).to eq(
        ["|key, value, *rest, last, flag: 1, **opts, &blk|"]
      )
    end

    it "emits nothing for a block with empty parameter pipes" do
      expect(mutations_for("empty_pipes")).to be_empty
    end

    it "flattens a group beside a block-pass parameter" do
      muts = mutations_for("group_with_block_param_sibling")

      expect(mutated_parameters(muts, "group_with_block_param_sibling")).to eq(["|key, value, &blk|"])
    end

    # With a lone group the two forms bind identically for a single yielded
    # array, which is what iteration yields, so the mutation would be
    # behaviour-preserving.
    it "emits nothing for a lone group" do
      expect(mutations_for("lone_group")).to be_empty
    end

    # A block-local is not a parameter, so the group is still alone.
    it "emits nothing for a lone group beside a block-local variable" do
      expect(mutations_for("lone_group_with_block_local")).to be_empty
    end

    it "emits nothing for flat parameters" do
      expect(mutations_for("flat_params")).to be_empty
    end

    it "emits nothing for a block without parameters" do
      expect(mutations_for("no_params")).to be_empty
    end

    it "emits nothing for a block using numbered parameters" do
      expect(mutations_for("numbered_param")).to be_empty
    end

    # A lambda checks its arity, so flattening raises ArgumentError on every
    # call rather than changing how the arguments bind.
    it "emits nothing for a lambda" do
      expect(mutations_for("lambda_with_group")).to be_empty
    end

    # A method signature binds by arity too, so flattening breaks every caller.
    it "emits nothing for a method parameter group" do
      expect(mutations_for("method_with_group")).to be_empty
    end

    it "mutates each block of a nested pair" do
      muts = mutations_from_source(
        "def m(rows)\n  rows.each { |(a, b), i| b.each { |(c, d), j| touch(a, b, c, d, i, j) } }\nend\n"
      )

      expect(muts.length).to eq(2)
    end

    it "reports the mutation on the line of the block" do
      muts = mutations_for("group_then_sibling")

      expect(muts.map(&:line)).to eq([6])
    end

    it "names the operator" do
      muts = mutations_for("group_then_sibling")

      expect(muts.map(&:operator_name)).to eq(["block_destructuring_expansion"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("group_then_sibling") + mutations_for("nested_group") +
             mutations_for("splat_inside_group") + mutations_for("do_end_form")

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["multi_target"])

      muts = described_class.new.call(subject_for("group_then_sibling"), filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
