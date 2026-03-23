# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::CompoundAssignment do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/compound_assignment.rb", __dir__) }
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
    it "replaces += with -=" do
      muts = mutations_for("add_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x -= 1") }).to be true
    end

    it "replaces += with *=" do
      muts = mutations_for("add_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x *= 1") }).to be true
    end

    it "replaces -= with +=" do
      muts = mutations_for("sub_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x += 1") }).to be true
    end

    it "replaces *= with /=" do
      muts = mutations_for("mul_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x /= 2") }).to be true
    end

    it "replaces /= with *=" do
      muts = mutations_for("div_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x *= 2") }).to be true
    end

    it "replaces %= with *=" do
      muts = mutations_for("mod_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x *= 3") }).to be true
    end

    it "replaces **= with *=" do
      muts = mutations_for("pow_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x *= 2") }).to be true
    end

    it "generates correct number of mutations for +=" do
      muts = mutations_for("add_assign")

      expect(muts.length).to eq(2)
    end

    it "generates one mutation for single-replacement operators" do
      muts = mutations_for("mod_assign")

      expect(muts.length).to eq(1)
    end

    it "mutates instance variable compound assignments" do
      muts = mutations_for("ivar_add_assign")

      expect(muts.any? { |m| m.mutated_source.include?("@count -= 1") }).to be true
    end

    it "mutates class variable compound assignments" do
      muts = mutations_for("cvar_add_assign")

      expect(muts.any? { |m| m.mutated_source.include?("@@total -= 1") }).to be true
    end

    it "mutates global variable compound assignments" do
      muts = mutations_for("gvar_add_assign")

      expect(muts.any? { |m| m.mutated_source.include?("$counter -= 1") }).to be true
    end

    it "replaces &= with |= and ^=" do
      muts = mutations_for("bitwise_and_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x |= 0xFF") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("x ^= 0xFF") }).to be true
    end

    it "replaces |= with &=" do
      muts = mutations_for("bitwise_or_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x &= 0x01") }).to be true
    end

    it "replaces ^= with &=" do
      muts = mutations_for("bitwise_xor_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x &= 0x0F") }).to be true
    end

    it "replaces <<= with >>=" do
      muts = mutations_for("left_shift_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x >>= 2") }).to be true
    end

    it "replaces >>= with <<=" do
      muts = mutations_for("right_shift_assign")

      expect(muts.any? { |m| m.mutated_source.include?("x <<= 2") }).to be true
    end

    it "generates correct number of mutations for &=" do
      muts = mutations_for("bitwise_and_assign")

      expect(muts.length).to eq(2)
    end

    it "replaces &&= with ||=" do
      muts = mutations_for("logical_and_assign")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("x ||= true")
    end

    it "replaces ||= with &&=" do
      muts = mutations_for("logical_or_assign")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('x &&= "default"')
    end

    it "mutates instance variable &&=" do
      muts = mutations_for("ivar_logical_and_assign")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("@flag ||= false")
    end

    it "mutates instance variable ||=" do
      muts = mutations_for("ivar_logical_or_assign")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('@ivar_logical_or_assign &&= "unknown"')
    end

    it "mutates class variable &&=" do
      muts = mutations_for("cvar_logical_and_assign")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("@@flag ||= false")
    end

    it "mutates class variable ||=" do
      muts = mutations_for("cvar_logical_or_assign")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('@@cvar_logical_or_assign &&= "unknown"')
    end

    it "mutates global variable &&=" do
      muts = mutations_for("gvar_logical_and_assign")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("$flag ||= false")
    end

    it "mutates global variable ||=" do
      muts = mutations_for("gvar_logical_or_assign")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('$gvar_logical_or_assign &&= "unknown"')
    end

    it "does not mutate methods with no compound assignments" do
      muts = mutations_for("no_compound_assignment")

      expect(muts).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result).not_to be_failure,
                                "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("add_assign")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("compound_assignment")
      end
    end
  end
end
