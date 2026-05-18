# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ExplicitSuperMutation do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/explicit_super.rb", __dir__) }
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name)
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subject)
  end

  def mutations_from_source(method_name, body)
    tmpfile = Tempfile.new(["explicit_super", ".rb"])
    tmpfile.write(body)
    tmpfile.close
    subj = Evilution::AST::Parser.new.call(tmpfile.path)
                                 .find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subj)
  ensure
    tmpfile.unlink if tmpfile
  end

  describe "#call" do
    context "with multiple arguments" do
      it "removes all arguments" do
        muts = mutations_for("with_args")

        strip_args = muts.find { |m| m.mutated_source.include?("super()") }
        expect(strip_args).not_to be_nil
      end

      it "removes individual arguments" do
        muts = mutations_for("with_args")

        remove_first = muts.find { |m| m.mutated_source.include?("super(b)") }
        remove_second = muts.find { |m| m.mutated_source.include?("super(a)") }
        expect(remove_first).not_to be_nil
        expect(remove_second).not_to be_nil
      end

      it "replaces with zsuper" do
        muts = mutations_for("with_args")

        zsuper = muts.find { |m| m.mutated_source.match?(/super\s*\n/) }
        expect(zsuper).not_to be_nil
      end

      it "produces four mutations total" do
        muts = mutations_for("with_args")

        expect(muts.length).to eq(4)
      end
    end

    context "with single argument" do
      it "removes all arguments" do
        muts = mutations_for("with_single_arg")

        strip_args = muts.find { |m| m.mutated_source.include?("super()") }
        expect(strip_args).not_to be_nil
      end

      it "replaces with zsuper" do
        muts = mutations_for("with_single_arg")

        zsuper = muts.find { |m| m.mutated_source.match?(/super\s*\n/) }
        expect(zsuper).not_to be_nil
      end

      it "does not remove individual arguments" do
        muts = mutations_for("with_single_arg")

        expect(muts.length).to eq(2)
      end
    end

    context "with no arguments" do
      it "replaces with zsuper" do
        muts = mutations_for("with_no_args")

        zsuper = muts.find { |m| m.mutated_source.match?(/super\s*\n/) }
        expect(zsuper).not_to be_nil
      end

      it "produces one mutation" do
        muts = mutations_for("with_no_args")

        expect(muts.length).to eq(1)
      end
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          expect { Prism.parse(mutation.mutated_source) }.not_to raise_error,
                                                                 "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("with_args")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("explicit_super_mutation")
      end
    end

    it "does not mutate methods without super" do
      muts = mutations_for("no_super")

      expect(muts).to be_empty
    end

    describe "argument-list boundary handling" do
      it "strips the closing paren region when removing all args (no leftover space)" do
        muts = mutations_from_source(
          "spaced", "class C\n  def spaced(a, b)\n    super(a, b )\n  end\nend\n"
        )

        strip_all = muts.find { |m| m.mutated_source.match?(/super\(\s*\)/) }
        expect(strip_all).not_to be_nil
        # The args-and-trailing-space must both go: `super()` exactly.
        expect(strip_all.mutated_source).to include("super()")
        expect(strip_all.mutated_source).not_to match(/super\( \)/)
      end

      it "handles a parenless super with arguments without error" do
        muts = mutations_from_source(
          "parenless", "class C\n  def parenless(a, b)\n    super a, b\n  end\nend\n"
        )

        expect(muts).not_to be_empty
        expect(muts.map(&:parse_status)).to all(eq(:ok))
        # Removing all args from a parenless super collapses to bare `super`.
        expect(muts.map(&:mutated_source)).to include(a_string_matching(/super\s*$/))
      end
    end

    describe "nested super recursion" do
      it "mutates a super call nested inside another super's arguments" do
        muts = mutations_from_source(
          "nested", "class C\n  def nested\n    super(super(1, 2), 3)\n  end\nend\n"
        )

        # The inner super(1, 2) is only reachable through visitor recursion.
        expect(muts.map(&:mutated_source)).to include(
          a_string_matching(/super\(super, 3\)/),
          a_string_matching(/super\(super\(1\), 3\)/),
          a_string_matching(/super\(super\(2\), 3\)/)
        )
      end
    end

    describe "dangling-comma safety" do
      # EV-05tp (#1215): stripping splat from `super(*x, &block)` left the
      # comma between args and block in place, producing `super(, &block)`.
      # The byte range used to remove args must include the trailing
      # separator before the block argument.
      it "produces parseable mutations when removing the splat in front of a block" do
        muts = mutations_for("with_splat_and_block")

        expect(muts).not_to be_empty
        expect(muts.map(&:parse_status)).to all(eq(:ok))
        # The empty-args variant must drop the splat AND the comma, keeping
        # the block.
        no_args_block = muts.find do |m|
          plus_line = m.diff.lines.find { |l| l.start_with?("+") }
          plus_line && plus_line.include?("super(&block)")
        end
        expect(no_args_block).not_to be_nil,
                                     "Expected `super(&block)` mutation; got: #{muts.map(&:diff).inspect}"
      end

      it "produces parseable mutations when stripping all args in front of a block" do
        muts = mutations_for("with_args_and_block")

        expect(muts).not_to be_empty
        expect(muts.map(&:parse_status)).to all(eq(:ok))
        no_args_block = muts.find do |m|
          plus_line = m.diff.lines.find { |l| l.start_with?("+") }
          plus_line && plus_line.include?("super(&block)")
        end
        expect(no_args_block).not_to be_nil
      end

      it "produces parseable mutations for splat-only super without block" do
        muts = mutations_for("with_splat_only")

        expect(muts).not_to be_empty
        expect(muts.map(&:parse_status)).to all(eq(:ok))
      end
    end
  end
end
