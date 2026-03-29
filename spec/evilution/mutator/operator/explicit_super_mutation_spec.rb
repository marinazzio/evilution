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
  end
end
