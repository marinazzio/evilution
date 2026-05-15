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

    it "emits a super-replacement when body already calls super (heuristic: super target presumed intended)" do
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

    it "replaces only the statements (not the def framing) for a method-level rescue" do
      muts = mutations_for("with_method_rescue")

      expect(muts.length).to eq(2)
      muts.each do |mutation|
        expect(mutation.mutated_source).to match(/rescue StandardError => e/)
        result = Prism.parse(mutation.mutated_source)
        expect(result.errors).to be_empty
      end
    end

    it "emits a parseable super-replacement for a method-level rescue whose body calls super" do
      muts = mutations_for("with_super_and_method_rescue")

      expect(muts.length).to eq(3)
      super_mut = muts.find { |m| m.mutated_source.match?(/^\s*super\n\s*rescue StandardError => e/) }
      expect(super_mut).not_to be_nil
      expect(Prism.parse(super_mut.mutated_source).errors).to be_empty
    end

    it "replaces only the statements for a method-level ensure" do
      muts = mutations_for("with_method_ensure")

      expect(muts.length).to eq(2)
      muts.each do |mutation|
        expect(mutation.mutated_source).to match(/ensure\n\s+cleanup/)
        expect(Prism.parse(mutation.mutated_source).errors).to be_empty
      end
    end

    it "emits a super-replacement when super lives only in the rescue clause" do
      muts = mutations_for("with_super_only_in_rescue")

      expect(muts.length).to eq(3)
      super_mut = muts.find { |m| m.mutated_source.match?(/^\s*super\n\s*rescue StandardError/) }
      expect(super_mut).not_to be_nil
      expect(Prism.parse(super_mut.mutated_source).errors).to be_empty
    end

    it "generates 0 mutations for a method-level rescue with no body statements" do
      muts = mutations_for("only_rescue_no_body")

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
