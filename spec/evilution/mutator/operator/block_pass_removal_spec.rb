# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BlockPassRemoval do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/block_pass_removal.rb", __dir__) }
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
    it "removes &:symbol block pass" do
      muts = mutations_for("with_symbol_block_pass")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.map\n  end")
    end

    it "removes &:predicate? block pass" do
      muts = mutations_for("with_predicate_block_pass")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.select\n")
      expect(muts.first.mutated_source).not_to include("&:valid?")
    end

    it "skips calls without a block" do
      muts = mutations_for("no_block_pass")

      expect(muts).to be_empty
    end

    it "skips calls with regular blocks (not block pass)" do
      muts = mutations_for("with_regular_block")

      expect(muts).to be_empty
    end

    it "removes &method(:name) block pass" do
      muts = mutations_for("with_method_object_block_pass")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.map\n")
      expect(muts.first.mutated_source).not_to include("&method")
    end

    it "removes each block pass in chained calls" do
      muts = mutations_for("chained_with_block_pass")

      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?("items.select.map(&:to_s)") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("items.select(&:present?).map\n") }).to be true
    end

    it "removes block pass when call has positional arguments" do
      muts = mutations_for("with_args_and_block_pass")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.inject(0)")
      expect(muts.first.mutated_source).not_to include("&:+")
    end

    it "removes block pass from call without receiver" do
      muts = mutations_for("block_pass_no_args")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("each\n")
      expect(muts.first.mutated_source).not_to include("&:freeze")
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "Invalid Ruby produced for #{mutation}: #{result.errors.map(&:message)}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("with_symbol_block_pass")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("block_pass_removal")
      end
    end
  end
end
