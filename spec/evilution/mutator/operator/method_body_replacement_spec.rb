# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::MethodBodyReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/method_body.rb", __dir__) }
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
    it "generates 2 mutations for a method without super in body (nil + self only)" do
      muts = mutations_for("with_body")

      expect(muts.length).to eq(2)
    end

    it "replaces body with nil" do
      muts = mutations_for("with_body")

      nil_mut = muts.find { |m| m.mutated_source.match?(/def with_body\s+nil\s+end/) }
      expect(nil_mut).not_to be_nil
    end

    it "replaces body with self" do
      muts = mutations_for("with_body")

      self_mut = muts.find { |m| m.mutated_source.match?(/def with_body\s+self\s+end/) }
      expect(self_mut).not_to be_nil
    end

    it "does not emit a super-replacement when body lacks super (avoids NoMethodError at runtime)" do
      muts = mutations_for("with_body")

      super_mut = muts.find { |m| m.mutated_source.match?(/def with_body\s+super\s+end/) }
      expect(super_mut).to be_nil
    end

    it "emits a super-replacement when body already calls super (proven safe in context)" do
      muts = mutations_for("with_super_in_body")

      expect(muts.length).to eq(3)
      super_mut = muts.find { |m| m.mutated_source.match?(/def with_super_in_body\s+super\s+end/) }
      expect(super_mut).not_to be_nil
    end

    it "emits a super-replacement when body calls forwarding super" do
      muts = mutations_for("with_forwarding_super")

      expect(muts.length).to eq(3)
    end

    it "generates 0 mutations for an empty method" do
      muts = mutations_for("empty_method")

      expect(muts.length).to eq(0)
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
      muts = mutations_for("with_body")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("method_body_replacement")
      end
    end
  end
end
