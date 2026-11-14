# frozen_string_literal: true

RSpec.describe Evilution::Cache::Skeleton do
  let(:source) { "class A\n  LIMIT = 3\n  def foo\n    1\n  end\n\n  def bar\n    2\n  end\nend\n" }

  def span(text, of: source)
    start = of.index(text)
    start...(start + text.bytesize)
  end

  def digest(src, texts)
    described_class.digest(src, texts.map { |text| span(text, of: src) })
  end

  it "stays the same when only a subject's own text changes" do
    edited = source.sub("    1\n", "    1 + 1\n    3\n")

    expect(digest(edited, ["def foo\n    1 + 1\n    3\n  end", "def bar\n    2\n  end"]))
      .to eq(digest(source, ["def foo\n    1\n  end", "def bar\n    2\n  end"]))
  end

  it "changes when code outside every subject changes" do
    edited = source.sub("LIMIT = 3", "LIMIT = 4")
    subjects = ["def foo\n    1\n  end", "def bar\n    2\n  end"]

    expect(digest(edited, subjects)).not_to eq(digest(source, subjects))
  end

  it "tells apart text moved from one side of a subject to the other" do
    left = "xydef a; endz"
    right = "xdef a; endyz"

    expect(digest(left, ["def a; end"])).not_to eq(digest(right, ["def a; end"]))
  end

  it "is the file outside the spans, a marker in place of each" do
    expect(described_class.digest("abcdefgh", [2...4, 6...7]))
      .to eq(Digest::SHA256.hexdigest("ab\0ef\0h"))
  end

  it "changes when code between two subjects changes" do
    subjects = ["def foo\n    1\n  end", "def bar\n    2\n  end"]
    edited = source.sub("  end\n\n  def bar", "  end\n  attr_reader :x\n\n  def bar")

    expect(digest(edited, subjects)).not_to eq(digest(source, subjects))
  end

  it "folds spans that overlap without nesting" do
    expect(described_class.digest("abcdefghij", [2...6, 4...9])).to eq(described_class.digest("abcdefghij", [2...9]))
  end

  it "folds an overlap that comes after other spans" do
    expect(described_class.digest("abcdefghijkl", [0...2, 5...8, 7...10]))
      .to eq(described_class.digest("abcdefghijkl", [0...2, 5...10]))
  end

  it "accepts a span that ends where the file does" do
    expect(described_class.digest("abcd", [2...4])).to eq(Digest::SHA256.hexdigest("ab\0"))
  end

  it "accepts overlapping and nested spans" do
    outer = "def foo\n    1\n  end"
    inner = "1"
    expect(described_class.digest(source, [span(outer), span(inner, of: source)].reverse))
      .to eq(described_class.digest(source, [span(outer)]))
  end

  it "digests the whole file when a span is unknown" do
    expect(described_class.digest(source, [span("def foo\n    1\n  end"), nil]))
      .to eq(described_class.digest(source, []))
  end

  it "digests the whole file when a span falls outside it" do
    expect(described_class.digest(source, [0...(source.bytesize + 5)]))
      .to eq(described_class.digest(source, []))
  end
end
