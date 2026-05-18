# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::LambdaBody do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/lambda_body.rb", __dir__) }
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

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["lambda_body", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "replaces lambda body with nil" do
      muts = mutations_for("simple_lambda")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("-> { nil }")
    end

    it "replaces lambda body with args" do
      muts = mutations_for("lambda_with_args")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("->(x) { nil }")
    end

    it "replaces multiline lambda body" do
      muts = mutations_for("lambda_with_multiline_body")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("nil")
      expect(muts.first.mutated_source).not_to include("y = x * 2")
    end

    it "skips empty lambda" do
      muts = mutations_for("empty_lambda")

      expect(muts).to be_empty
    end

    it "generates one mutation per lambda" do
      muts = mutations_for("multiple_lambdas")

      expect(muts.length).to eq(2)
    end

    it "recurses into a nested lambda so the inner lambda body is also replaced" do
      muts = mutations_from_source("class C\n  def m\n    -> { -> { 1 } }\n  end\nend\n")

      expect(muts.length).to eq(2)
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
      muts = mutations_for("simple_lambda")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("lambda_body")
      end
    end
  end
end
