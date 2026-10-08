# frozen_string_literal: true

require "openssl"

RSpec.describe Evilution::Mutator::Operator::IntegerLiteral do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/integer_literal.rb", __dir__) }
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
    it "replaces 0 with 1, -1, a width sentinel and nil" do
      muts = mutations_for("returns_zero")

      expect(muts.length).to eq(4)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_zero\s+1\s+end/),
        a_string_matching(/def returns_zero\s+-1\s+end/),
        a_string_matching(/def returns_zero\s+nil\s+end/)
      )
    end

    it "replaces 1 with 0, a width sentinel and nil" do
      muts = mutations_for("returns_one")

      expect(muts.length).to eq(3)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_one\s+0\s+end/),
        a_string_matching(/def returns_one\s+nil\s+end/)
      )
    end

    it "replaces 42 with 0, 43, 41, a width sentinel and nil" do
      muts = mutations_for("returns_forty_two")

      expect(muts.length).to eq(5)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_forty_two\s+0\s+end/),
        a_string_matching(/def returns_forty_two\s+43\s+end/),
        a_string_matching(/def returns_forty_two\s+41\s+end/),
        a_string_matching(/def returns_forty_two\s+nil\s+end/)
      )
    end

    it "lowers a negative literal" do
      mutated_sources = mutations_for("returns_minus_five").map(&:mutated_source)

      expect(mutated_sources).to include(a_string_matching(/def returns_minus_five\s+-6\s+end/))
    end

    it "replaces -1 with 0, -2, a width sentinel and nil, the 0 once" do
      muts = mutations_for("returns_minus_one")

      expect(muts.length).to eq(4)
      mutated_sources = muts.map(&:mutated_source)
      expect(mutated_sources).to include(
        a_string_matching(/def returns_minus_one\s+0\s+end/),
        a_string_matching(/def returns_minus_one\s+-2\s+end/),
        a_string_matching(/def returns_minus_one\s+nil\s+end/)
      )
    end

    it "keeps a subtraction written without spaces valid" do
      mutation = mutations_for("subtracts_zero").find { |m| m.mutated_source.include?("count--1") }

      expect(mutation).not_to be_nil
      expect(Prism.parse(mutation.mutated_source).success?).to be(true)
    end

    it "keeps an argument written without parentheses an argument" do
      mutation = mutations_for("passes_zero").find { |m| m.mutated_source.include?("record -1") }
      expect(mutation).not_to be_nil

      call = Prism.parse(mutation.mutated_source).value.statements.body.first.body.body.last.body.body.first

      expect(call.name).to eq(:record)
      expect(call.arguments.arguments.map(&:slice)).to eq(["-1"])
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

    describe "width sentinel" do
      # The replacements of one literal, in the order they are emitted.
      def replacements_of(literal)
        Tempfile.create(["integer_literal", ".rb"]) do |file|
          File.write(file.path, "class Sample\n  def value\n    #{literal}\n  end\nend\n")
          subject = Evilution::AST::Parser.new.call(file.path).first
          described_class.new.call(subject).map { |m| m.mutated_source.lines[2].strip }
        end
      end

      {
        "0" => "167",
        "127" => "167",
        "128" => "467",
        "255" => "467",
        "256" => "55487",
        "32_767" => "55487",
        "32_768" => "108503",
        "65_535" => "108503",
        "65_536" => "2667278543",
        "2_147_483_647" => "2667278543",
        "2_147_483_648" => "7980081959",
        "4_294_967_295" => "7980081959",
        "4_294_967_296" => "15508464536481899903",
        "9_223_372_036_854_775_807" => "15508464536481899903"
      }.each do |literal, sentinel|
        it "replaces #{literal} with #{sentinel}" do
          expect(replacements_of(literal)).to include(sentinel)
        end
      end

      # A safe prime is a prime p whose (p - 1) / 2 is prime too.
      it "keeps every sentinel a safe prime inside its own width zone" do
        ceilings = [*described_class::WIDTH_SENTINELS.keys.drop(1), 2**64]

        described_class::WIDTH_SENTINELS.each_with_index do |(boundary, sentinel), index|
          expect(OpenSSL::BN.new(sentinel)).to be_prime
          expect(OpenSSL::BN.new((sentinel - 1) / 2)).to be_prime
          expect(sentinel).to be_between(boundary, ceilings[index] - 1)
        end
      end

      it "emits it after the neighbours and before nil" do
        expect(replacements_of("42")).to eq(%w[0 43 41 167 nil])
      end

      it "goes by the magnitude of a negative literal" do
        expect(replacements_of("-127")).to eq(%w[0 -126 -128 167 nil])
        expect(replacements_of("-128")).to eq(%w[0 -127 -129 467 nil])
      end

      it "emits none from 2**63 up" do
        expect(replacements_of("9_223_372_036_854_775_808"))
          .to eq(%w[0 9223372036854775809 9223372036854775807 nil])
        expect(replacements_of("-9_223_372_036_854_775_808"))
          .to eq(%w[0 -9223372036854775807 -9223372036854775809 nil])
      end
    end

    # ComplexLiteral replaces the literal as a whole; `nili` is not a value.
    it "leaves the integer part of a complex literal alone" do
      Tempfile.create(["integer_literal", ".rb"]) do |file|
        File.write(file.path, "class Sample\n  def value\n    5i + 2\n  end\nend\n")
        mutations = described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)

        expect(mutations.map { |m| m.mutated_source.lines[2].strip }).to eq(["5i + 0", "5i + 3", "5i + 1", "5i + 167", "5i + nil"])
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("returns_zero")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("integer_literal")
      end
    end
  end
end
