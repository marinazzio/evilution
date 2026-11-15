# frozen_string_literal: true

require "diff/lcs"
require "evilution/mutation"

RSpec.describe Evilution::Mutation::LineDiff do
  # What the diff was before it looked at the changed lines only: Diff::LCS
  # over every line of both sources.
  def whole_file_diff(original, mutated)
    changes = Diff::LCS.diff(original.lines, mutated.lines).flatten(1)
    changes.map { |change| "#{change.action} #{change.element.chomp}" }.join("\n")
  end

  def diff(original, mutated)
    described_class.call(original, mutated)
  end

  it "lists the removed lines, then the added ones" do
    expect(diff("a\nb\nc\n", "a\nB\nc\n")).to eq("- b\n+ B")
  end

  it "is empty for identical sources" do
    expect(diff("a\nb\n", "a\nb\n")).to eq("")
  end

  it "lists a removed line" do
    expect(diff("a\nb\nc\n", "a\nc\n")).to eq("- b")
  end

  it "lists an added line" do
    expect(diff("a\nc\n", "a\nb\nc\n")).to eq("+ b")
  end

  it "lists a change to a last line with no line break" do
    expect(diff("a\nb", "a\nB")).to eq("- b\n+ B")
  end

  it "tells a last line with a line break from one without" do
    expect(diff("a\nb", "a\nb\n")).to eq(whole_file_diff("a\nb", "a\nb\n"))
  end

  it "lists the lines of an empty source" do
    expect(diff("", "a\n")).to eq("+ a")
    expect(diff("a\n", "")).to eq("- a")
  end

  it "keeps the source's encoding in the lines it lists" do
    result = diff("x = 1\ny = \"héllo\"\n", "x = 1\ny = \"\"\n")

    expect(result).to eq("- y = \"héllo\"\n+ y = \"\"")
    expect(result.encoding).to eq(Encoding::UTF_8)
  end

  it "lists the same lines Diff::LCS finds over the whole file where equal lines repeat around the change" do
    original = "x\nz\n"
    mutated = "x\ny\nx\nz\n"

    expect(diff(original, mutated)).to eq(whole_file_diff(original, mutated))
    expect(diff(original, mutated)).to eq("+ y\n+ x")
  end

  it "orders a change at the end of the file as Diff::LCS does over the whole file" do
    original = "a\nb\nc\n"
    mutated = "a\nB\nC\n"

    expect(diff(original, mutated)).to eq(whole_file_diff(original, mutated))
  end

  it "hands Diff::LCS only the lines between the equal ones, and one equal line after them" do
    original = (1..50).map { |i| "line #{i}\n" }.join
    mutated = original.sub("line 25\n", "line twenty-five\n")
    allow(Diff::LCS).to receive(:diff).and_call_original

    diff(original, mutated)

    expect(Diff::LCS).to have_received(:diff).with(["line 25\n", "line 26\n"], ["line twenty-five\n", "line 26\n"])
  end

  describe "the lines it hands Diff::LCS" do
    let(:calls) { [] }

    before do
      allow(Diff::LCS).to receive(:diff).and_wrap_original do |original, *args|
        calls << args
        original.call(*args)
      end
    end

    def handed(original, mutated)
      diff(original, mutated)
      expect(calls.length).to eq(1)
      calls.first
    end

    it "start at the first line that differs and end with the first equal line after a removed line" do
      expect(handed("a\nb\nc\nd\ne\n", "a\nc\nd\ne\n")).to eq([%W[b\n c\n], ["c\n"]])
    end

    it "end with the first equal line after an added line" do
      expect(handed("a\nc\nd\ne\n", "a\nb\nc\nd\ne\n")).to eq([["c\n"], %W[b\n c\n]])
    end

    it "start at the top of the file when its first line differs" do
      expect(handed("a\nb\nc\n", "A\nb\nc\n")).to eq([%W[a\n b\n], %W[A\n b\n]])
    end

    it "run to the end of the file when its last line differs" do
      expect(handed("a\nb\nc", "a\nb\nC")).to eq([["c"], ["C"]])
    end

    it "end with the first equal line after a change inside a line" do
      expect(handed("a\nbx\nc\nd\n", "a\nby\nc\nd\n")).to eq([%W[bx\n c\n], %W[by\n c\n]])
    end

    it "are none for identical sources" do
      diff("a\n", "a\n")

      expect(Diff::LCS).not_to have_received(:diff)
    end
  end

  it "finds what Diff::LCS finds over the whole file, whatever the change" do
    random = Random.new(1909)
    alphabet = %W[a\n b\n a\n c\n \n é\n a b]

    500.times do
      lines = Array.new(random.rand(0..12)) { "#{alphabet.sample(random: random).chomp}\n" }
      lines[-1] = lines[-1].chomp if lines.any? && random.rand(4).zero?
      original = lines.join
      cut = random.rand(0..lines.length)
      removed = random.rand(0..[lines.length - cut, 3].min)
      added = Array.new(random.rand(0..3)) { alphabet.sample(random: random) }
      mutated = (lines[0...cut] + added + lines[(cut + removed)..]).join

      expect(diff(original, mutated)).to eq(whole_file_diff(original, mutated)),
                                         "original #{original.inspect}, mutated #{mutated.inspect}"
    end
  end

  it "finds what Diff::LCS finds over the whole file for byte edits inside lines" do
    random = Random.new(42)
    pieces = ["a", "b", "\n", " ", "é", "x\n"]

    500.times do
      original = Array.new(random.rand(0..30)) { pieces.sample(random: random) }.join
      offset = random.rand(0..original.bytesize)
      length = random.rand(0..[original.bytesize - offset, 6].min)
      replacement = Array.new(random.rand(0..4)) { pieces.sample(random: random) }.join
      mutated = original.b.tap { |bytes| bytes[offset, length] = replacement.b }.force_encoding(Encoding::UTF_8)

      expect(diff(original, mutated)).to eq(whole_file_diff(original, mutated)),
                                         "original #{original.inspect}, mutated #{mutated.inspect}"
    end
  end
end
