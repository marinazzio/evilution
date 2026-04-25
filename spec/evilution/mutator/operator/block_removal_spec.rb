# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BlockRemoval do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/block_removal.rb", __dir__) }
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
    it "removes brace block from method call" do
      muts = mutations_for("with_block")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.map\n")
      expect(muts.first.mutated_source).not_to include("items.map {")
    end

    it "removes do..end block from method call" do
      muts = mutations_for("with_do_block")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.each\n")
      expect(muts.first.mutated_source).not_to include("items.each do")
    end

    it "skips calls without a block" do
      muts = mutations_for("no_block")

      expect(muts).to be_empty
    end

    it "removes block from self.method call" do
      muts = mutations_for("with_self_block")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("self.tap\n")
      expect(muts.first.mutated_source).not_to include("self.tap {")
    end

    it "handles chained calls with blocks by removing each block" do
      muts = mutations_for("chained_blocks")

      expect(muts.length).to eq(2)
      # Remove block from .select
      expect(muts.any? { |m| m.mutated_source.include?("items.select.map { |x| x.to_s }") }).to be true
      # Remove block from .map
      expect(muts.any? { |m| m.mutated_source.include?(".map\n") && !m.mutated_source.include?("x.to_s") }).to be true
    end

    it "removes block from call without receiver" do
      muts = mutations_for("block_no_receiver")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("loop\n")
      expect(muts.first.mutated_source).not_to include("loop {")
    end

    it "skips block-pass arguments (&:sym) — stripping them inside parens yields invalid Ruby" do
      muts = mutations_for("block_pass_symbol")

      expect(muts).to be_empty
    end

    it "skips block-pass argument on index_by(&:id)" do
      muts = mutations_for("block_pass_index_by")

      expect(muts).to be_empty
    end

    it "still mutates an explicit brace block in a chain even when other links use block-pass" do
      muts = mutations_for("chained_block_pass")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.flat_map.compact.map!(&:upcase)")
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
      muts = mutations_for("with_block")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("block_removal")
      end
    end
  end
end
