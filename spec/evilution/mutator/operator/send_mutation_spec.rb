# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::SendMutation do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/send_mutation.rb", __dir__) }
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
    it "replaces flat_map with map" do
      muts = mutations_for("using_flat_map")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("[1, 2, 3].map {")
    end

    it "replaces map with flat_map" do
      muts = mutations_for("using_map")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".flat_map {")
    end

    it "replaces public_send with send" do
      muts = mutations_for("using_public_send")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".send(")
    end

    it "replaces send with public_send" do
      muts = mutations_for("using_send")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".public_send(")
    end

    it "replaces gsub with sub" do
      muts = mutations_for("using_gsub")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('"hello world".sub(')
    end

    it "replaces sub with gsub" do
      muts = mutations_for("using_sub")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".gsub(")
    end

    it "replaces detect with find" do
      muts = mutations_for("using_detect")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".find {")
    end

    it "replaces find with detect" do
      muts = mutations_for("using_find")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".detect {")
    end

    it "replaces collect with map" do
      muts = mutations_for("using_collect")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".map {")
    end

    it "replaces each_with_object with inject" do
      muts = mutations_for("using_each_with_object")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".inject(")
    end

    it "replaces reverse_each with each" do
      muts = mutations_for("using_reverse_each")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".each {")
    end

    it "replaces length with size" do
      muts = mutations_for("using_length")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".size")
    end

    it "replaces size with length" do
      muts = mutations_for("using_size")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".length")
    end

    it "replaces values_at with fetch_values" do
      muts = mutations_for("using_values_at")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".fetch_values(")
    end

    it "replaces fetch_values with values_at" do
      muts = mutations_for("using_fetch_values")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include(".values_at(")
    end

    it "handles nested calls with multiple replaceable methods" do
      muts = mutations_for("using_flat_map_and_map")

      expect(muts.length).to eq(2)
      replacements = muts.map(&:mutated_source)
      expect(replacements).to include(
        a_string_including(".map { |x|"),
        a_string_including(".flat_map { |y|")
      )
    end

    it "skips bare method calls without receiver" do
      muts = mutations_for("bare_method_call")

      expect(muts).to be_empty
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
      muts = mutations_for("using_flat_map")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("send_mutation")
      end
    end
  end
end
