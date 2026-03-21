# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::NilReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/nil_literal.rb", __dir__) }
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
    it "replaces nil with true, false, 0, and empty string" do
      muts = mutations_for("returns_nil")

      expect(muts.length).to eq(4)
      replacements = muts.map { |m| m.mutated_source[/def returns_nil\s+(.+)\s+end/, 1] }
      expect(replacements).to contain_exactly("true", "false", "0", '""')
    end

    it "replaces nil in conditional context with all variants" do
      muts = mutations_for("nil_with_logic")

      expect(muts.length).to eq(4)
      replacements = muts.map { |m| m.mutated_source[/return (.+) if flag/, 1] }
      expect(replacements).to contain_exactly("true", "false", "0", '""')
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
      muts = mutations_for("returns_nil")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("nil_replacement")
      end
    end
  end
end
