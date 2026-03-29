# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BitwiseReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/bitwise.rb", __dir__) }
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
    it "replaces & with | and ^" do
      muts = mutations_for("bitwise_and")

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_including("a | b"),
        a_string_including("a ^ b")
      )
    end

    it "replaces | with & and ^" do
      muts = mutations_for("bitwise_or")

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_including("a & b"),
        a_string_including("a ^ b")
      )
    end

    it "replaces ^ with & and |" do
      muts = mutations_for("bitwise_xor")

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_including("a & b"),
        a_string_including("a | b")
      )
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
      muts = mutations_for("bitwise_and")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("bitwise_replacement")
      end
    end

    it "does not mutate methods with no bitwise operators" do
      plain_source = "class Foo\n  def greet\n    'hello'\n  end\nend"
      plain_path = fixture_path
      tree = Prism.parse(plain_source).value
      finder = Evilution::AST::SubjectFinder.new(plain_source, plain_path)
      finder.visit(tree)
      subj = finder.subjects.find { |s| s.name.end_with?("#greet") }

      muts = described_class.new.call(subj)
      expect(muts).to be_empty
    end
  end
end
