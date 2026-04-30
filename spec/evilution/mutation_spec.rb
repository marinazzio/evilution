# frozen_string_literal: true

RSpec.describe Evilution::Mutation do
  let(:subject_double) { double("Subject", name: "User#adult?") }

  def build_mutation(**overrides)
    described_class.new(
      subject: subject_double,
      operator_name: "comparison_replacement",
      sources: described_class::Sources.new(
        original: "def adult?\n  @age >= 18\nend",
        mutated: "def adult?\n  @age > 18\nend"
      ),
      location: described_class::Location.new(file_path: "lib/user.rb", line: 9, column: 7),
      slice: described_class::Slice.new(original: "  @age >= 18\n", mutated: "  @age > 18\n"),
      **overrides
    )
  end

  let(:mutation) { build_mutation }

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

  it "exposes original_slice covering affected lines" do
    expect(mutation.original_slice).to eq("  @age >= 18\n")
  end

  it "exposes mutated_slice covering affected lines" do
    expect(mutation.mutated_slice).to eq("  @age > 18\n")
  end

  it "defaults slices to nil when slice is not provided" do
    m = build_mutation(slice: nil)

    expect(m.original_slice).to be_nil
    expect(m.mutated_slice).to be_nil
  end

  describe "#parse_status" do
    it "defaults to :ok" do
      expect(mutation.parse_status).to eq(:ok)
    end

    it "accepts :unparseable" do
      m = build_mutation(parse_status: :unparseable)

      expect(m.parse_status).to eq(:unparseable)
      expect(m).to be_unparseable
    end

    it "reports #unparseable? false when :ok" do
      expect(mutation).not_to be_unparseable
    end
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

  describe "#diff" do
    it "returns a unified diff of the change" do
      result = mutation.diff

      expect(result).to include("-   @age >= 18")
      expect(result).to include("+   @age > 18")
    end

    it "returns empty string when sources are identical" do
      m = build_mutation(
        sources: described_class::Sources.new(original: "x = 1", mutated: "x = 1")
      )

      expect(m.diff).to eq("")
    end
  end

  describe "#unified_diff" do
    it "returns a git-style unified diff with file header and hunk header" do
      result = mutation.unified_diff

      expect(result).to include("--- a/lib/user.rb")
      expect(result).to include("+++ b/lib/user.rb")
      expect(result).to include("@@ -9,1 +9,1 @@")
      expect(result).to include("-  @age >= 18")
      expect(result).to include("+  @age > 18")
    end

    it "returns nil when slice is missing" do
      m = build_mutation(slice: nil)

      expect(m.unified_diff).to be_nil
    end

    it "renders multi-line slices with correct line counts" do
      m = build_mutation(
        sources: described_class::Sources.new(original: "a", mutated: "b"),
        location: described_class::Location.new(file_path: "x.rb", line: 3, column: 0),
        slice: described_class::Slice.new(original: "  a\n  b\n", mutated: "  a\n  c\n")
      )

      result = m.unified_diff

      expect(result).to include("@@ -3,2 +3,2 @@")
      expect(result).to include("   a")
      expect(result).to include("-  b")
      expect(result).to include("+  c")
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
