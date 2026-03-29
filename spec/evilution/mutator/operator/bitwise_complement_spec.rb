# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BitwiseComplement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/bitwise_complement.rb", __dir__) }
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
    it "removes ~ to unwrap the operand" do
      muts = mutations_for("complement")

      removal = muts.find { |m| m.mutated_source.include?("    a\n") }
      expect(removal).not_to be_nil
    end

    it "swaps ~ with unary minus" do
      muts = mutations_for("complement")

      swap = muts.find { |m| m.mutated_source.include?("-a") }
      expect(swap).not_to be_nil
    end

    it "produces two mutations per ~ operator" do
      muts = mutations_for("complement")

      expect(muts.length).to eq(2)
    end

    it "handles ~ on expressions" do
      muts = mutations_for("complement_expression")

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_including("(a + b)"),
        a_string_including("-(a + b)")
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
      muts = mutations_for("complement")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("bitwise_complement")
      end
    end

    it "does not mutate methods with no complement operators" do
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
