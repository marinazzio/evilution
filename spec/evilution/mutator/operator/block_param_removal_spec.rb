# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BlockParamRemoval do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/block_param_removal.rb", __dir__) }
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
    it "removes block param when it is the only parameter" do
      muts = mutations_for("only_block_param")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("def only_block_param\n")
    end

    it "removes block param while keeping other parameters" do
      muts = mutations_for("with_other_params")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("def with_other_params(a, b)\n")
    end

    it "removes block param with keyword parameters" do
      muts = mutations_for("with_keyword_and_block")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("def with_keyword_and_block(name:)\n")
    end

    it "skips methods without block param" do
      muts = mutations_for("no_block_param")

      expect(muts).to be_empty
    end

    it "skips methods without parameters" do
      muts = mutations_for("no_params")

      expect(muts).to be_empty
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
      muts = mutations_for("only_block_param")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("block_param_removal")
      end
    end
  end
end
