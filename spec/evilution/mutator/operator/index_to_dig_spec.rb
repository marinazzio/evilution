# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IndexToDig do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/nested_index.rb", __dir__) }
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
    it "replaces h[:a][:b] with h.dig(:a, :b)" do
      muts = mutations_for("two_level")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.dig(:a, :b)")
    end

    it "replaces h[:a][:b][:c] with h.dig(:a, :b, :c)" do
      muts = mutations_for("three_level")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.dig(:a, :b, :c)")
    end

    it "handles mixed key types" do
      muts = mutations_for("mixed_keys")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('h.dig("users", 0, :name)')
    end

    it "does not mutate single-level [] access" do
      muts = mutations_for("single_level")

      expect(muts).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("two_level")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("index_to_dig")
      end
    end

    it "does not mutate methods without [] access" do
      muts = mutations_for("no_index")

      expect(muts).to be_empty
    end

    it "recurses into a chain nested inside another index's argument" do
      # x[y[:a][:b]] — the outer x[...] is not dig-able, but the inner
      # y[:a][:b] argument is; reaching it requires descending past x[...].
      muts = mutations_for("nested_in_argument")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("x[y.dig(:a, :b)]")
    end

    it "does not mutate when an index is followed by a non-index method call" do
      # h[:a].bar — `.bar` is not an index call, so there is no [][] chain.
      muts = mutations_for("index_then_call")

      expect(muts).to be_empty
    end

    it "does not crash and mutates a self-receiver index chain" do
      # collect_chain walks receivers until one is not a [] call; the chain
      # root here is `self`, which has no #name method.
      expect { mutations_for("self_index") }.not_to raise_error

      muts = mutations_for("self_index")
      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("self.dig(:a, :b)")
    end

    it "does not mutate a chain of ordinary (non-[]) method calls" do
      # a.foo(1).bar(2) — single-arg calls, but the method name is not :[].
      muts = mutations_for("method_chain")

      expect(muts).to be_empty
    end

    it "does not crash and does not mutate an argument-less index call chain" do
      # h[][:b] — the inner h[] has no arguments; it is not a single-arg index.
      expect { mutations_for("empty_index_chain") }.not_to raise_error

      expect(mutations_for("empty_index_chain")).to be_empty
    end

    it "does not mutate when an index uses more than one argument" do
      # h[:a, :b][:c] — h[:a, :b] takes two arguments, so it is not a
      # single-arg index and the chain must not be collapsed to #dig.
      muts = mutations_for("two_arg_index")

      expect(muts).to be_empty
    end
  end
end
