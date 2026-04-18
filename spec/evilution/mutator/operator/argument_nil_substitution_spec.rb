# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ArgumentNilSubstitution do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/argument_nil_substitution.rb", __dir__) }
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
    it "replaces a single argument with nil" do
      muts = mutations_for("single_arg")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("transform(nil)")
    end

    it "replaces each argument with nil in a two-arg call" do
      muts = mutations_for("two_args")

      expect(muts.length).to eq(2)
      expect(muts.any? { |m| m.mutated_source.include?("obj.compute(nil, b)") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("obj.compute(a, nil)") }).to be true
    end

    it "replaces each argument with nil in a three-arg call" do
      muts = mutations_for("three_args")

      expect(muts.length).to eq(3)
      expect(muts.any? { |m| m.mutated_source.include?("process(nil, b, c)") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("process(a, nil, c)") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("process(a, b, nil)") }).to be true
    end

    it "skips calls with no arguments" do
      muts = mutations_for("no_args")

      expect(muts).to be_empty
    end

    it "works with receiver-qualified calls" do
      muts = mutations_for("with_receiver")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("I18n.with_locale(nil)")
    end

    it "skips calls with splat arguments" do
      muts = mutations_for("with_splat")

      expect(muts).to be_empty
    end

    it "skips calls with keyword arguments" do
      muts = mutations_for("with_kwargs")

      expect(muts).to be_empty
    end

    it "skips calls with block arguments" do
      muts = mutations_for("with_block_arg")

      expect(muts).to be_empty
    end

    it "skips index-assignment calls (hash/array []=)" do
      expect(mutations_for("index_assign")).to be_empty
      expect(mutations_for("multi_index_assign")).to be_empty
      expect(mutations_for("array_index_assign")).to be_empty
    end

    it "replaces string literal arguments with nil" do
      muts = mutations_for("string_arg")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("puts(nil)")
    end

    it "handles nested calls by replacing args at each level" do
      muts = mutations_for("nested_calls")

      # foo(bar(a), b) produces:
      # - foo(nil, b)       (replace first arg of foo)
      # - foo(bar(a), nil)  (replace second arg of foo)
      # - foo(bar(nil), b)  (replace arg of bar)
      expect(muts.length).to eq(3)
      expect(muts.any? { |m| m.mutated_source.include?("foo(nil, b)") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("foo(bar(a), nil)") }).to be true
      expect(muts.any? { |m| m.mutated_source.include?("foo(bar(nil), b)") }).to be true
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty,
                                   "Invalid Ruby produced for #{subj.name}: #{result.errors.map(&:message)}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("single_arg")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("argument_nil_substitution")
      end
    end
  end
end
