# frozen_string_literal: true

RSpec.describe Evilution::Mutation do
  let(:subject_double) { double("Subject", name: "User#adult?") }

  let(:mutation) do
    described_class.new(
      subject: subject_double,
      operator_name: "comparison_replacement",
      original_source: "def adult?\n  @age >= 18\nend",
      mutated_source: "def adult?\n  @age > 18\nend",
      file_path: "lib/user.rb",
      line: 9,
      column: 7
    )
  end

  it "exposes subject" do
    expect(mutation.subject).to eq(subject_double)
  end

  it "exposes operator_name" do
    expect(mutation.operator_name).to eq("comparison_replacement")
  end

  it "exposes original_source" do
    expect(mutation.original_source).to include("@age >= 18")
  end

  it "exposes mutated_source" do
    expect(mutation.mutated_source).to include("@age > 18")
  end

  it "exposes file_path" do
    expect(mutation.file_path).to eq("lib/user.rb")
  end

  it "exposes line" do
    expect(mutation.line).to eq(9)
  end

  it "exposes column" do
    expect(mutation.column).to eq(7)
  end

  it "defaults column to 0" do
    m = described_class.new(
      subject: subject_double,
      operator_name: "test",
      original_source: "a",
      mutated_source: "b",
      file_path: "x.rb",
      line: 1
    )

    expect(m.column).to eq(0)
  end

  describe "#diff" do
    it "returns a unified diff of the change" do
      result = mutation.diff

      expect(result).to include("-   @age >= 18")
      expect(result).to include("+   @age > 18")
    end

    it "returns empty string when sources are identical" do
      m = described_class.new(
        subject: subject_double,
        operator_name: "noop",
        original_source: "x = 1",
        mutated_source: "x = 1",
        file_path: "x.rb",
        line: 1
      )

      expect(m.diff).to eq("")
    end
  end

  describe "#to_s" do
    it "returns operator name with file and line" do
      expect(mutation.to_s).to eq("comparison_replacement: lib/user.rb:9")
    end
  end

  describe "#strip_sources!" do
    it "nils out original_source and mutated_source" do
      mutation.strip_sources!

      expect(mutation.original_source).to be_nil
      expect(mutation.mutated_source).to be_nil
    end

    it "preserves the diff after stripping" do
      expected_diff = mutation.diff

      mutation.strip_sources!

      expect(mutation.diff).to eq(expected_diff)
    end

    it "preserves other attributes after stripping" do
      mutation.strip_sources!

      expect(mutation.operator_name).to eq("comparison_replacement")
      expect(mutation.file_path).to eq("lib/user.rb")
      expect(mutation.line).to eq(9)
    end
  end
end
