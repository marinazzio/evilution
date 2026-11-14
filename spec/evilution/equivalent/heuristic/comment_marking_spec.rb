# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Heuristic::CommentMarking do
  subject(:heuristic) { described_class.new }

  it "matches when mutation line has inline evilution:equivalent comment" do
    source = "def foo\n  x > 0 # evilution:equivalent\nend\n"
    mutation = double("Mutation", original_source: source, line: 2)

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches when line above mutation has evilution:equivalent comment" do
    source = "def foo\n  # evilution:equivalent\n  x > 0\nend\n"
    mutation = double("Mutation", original_source: source, line: 3)

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches with extra whitespace around the marker" do
    source = "def foo\n  x > 0 #   evilution:equivalent  \nend\n"
    mutation = double("Mutation", original_source: source, line: 2)

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match when comment is on a different line" do
    source = "# evilution:equivalent\ndef foo\n  x > 0\nend\n"
    mutation = double("Mutation", original_source: source, line: 3)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not split a file that holds no marker into lines" do
    source = +"def foo\n  x > 0\nend\n"
    allow(source).to receive(:lines).and_call_original
    mutation = double("Mutation", original_source: source, line: 2)

    expect(heuristic.match?(mutation)).to be false
    expect(source).not_to have_received(:lines)
  end

  it "scans a file for the marker once for all its mutations" do
    source = +"def foo\n  x > 0\nend\n"
    allow(source).to receive(:match?).and_call_original

    heuristic.match?(double("Mutation", original_source: source, line: 2))
    heuristic.match?(double("Mutation", original_source: source, line: 1))

    expect(source).to have_received(:match?).once
  end

  it "keeps its answer for a marked file asked about again" do
    source = "def foo\n  x > 0 # evilution:equivalent\nend\n"

    expect(heuristic.match?(double("Mutation", original_source: source, line: 2))).to be true
    expect(heuristic.match?(double("Mutation", original_source: source, line: 2))).to be true
  end

  it "does not match a line past the end of a marked file" do
    source = "x = 1 # evilution:equivalent\n"

    expect(heuristic.match?(double("Mutation", original_source: source, line: 2))).to be false
  end

  it "matches a marker on the line right above, deep in the file" do
    source = "def foo\n  a = 1\n  # evilution:equivalent\n  x > 0\nend\n"

    expect(heuristic.match?(double("Mutation", original_source: source, line: 4))).to be true
  end

  it "does not match a mutation whose sources were released" do
    expect(heuristic.match?(double("Mutation", original_source: nil, line: 1))).to be false
  end

  it "scans another file anew" do
    heuristic.match?(double("Mutation", original_source: "x = 1\n", line: 1))

    expect(heuristic.match?(double("Mutation", original_source: "x = 1 # evilution:equivalent\n", line: 1))).to be true
  end

  it "does not match a marker that runs across a line break" do
    source = "def foo\n  x > 0 #\nevilution:equivalent\nend\n"
    mutation = double("Mutation", original_source: source, line: 2)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match when no comment is present" do
    source = "def foo\n  x > 0\nend\n"
    mutation = double("Mutation", original_source: source, line: 2)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match when original_source is nil" do
    mutation = double("Mutation", original_source: nil, line: 2)

    expect(heuristic.match?(mutation)).to be false
  end

  it "matches on first line with inline comment" do
    source = "x > 0 # evilution:equivalent\n"
    mutation = double("Mutation", original_source: source, line: 1)

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match a similar but incorrect marker" do
    source = "def foo\n  x > 0 # evilution:skip\nend\n"
    mutation = double("Mutation", original_source: source, line: 2)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match when the mutation line is past the end of the source" do
    # line 99 is far beyond the source; line_index is out of bounds.
    # The bounds guard must reject before indexing past the end.
    source = "def foo\n  x > 0\nend\n"
    mutation = double("Mutation", original_source: source, line: 99)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match when the mutation line is zero (negative line index)" do
    # line 0 yields line_index -1. Without the negative guard, lines[-1]
    # wraps to the last line; here the last line carries the marker, so a
    # missing guard would wrongly classify the mutation as equivalent.
    source = "def foo\n  x > 0\nend # evilution:equivalent\n"
    mutation = double("Mutation", original_source: source, line: 0)

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match the first line by wrapping to the last line's marker" do
    # line 1 -> line_index 0. The "line above" check must be gated on
    # line_index being positive; otherwise lines[0 - 1] wraps to the last
    # line, whose marker would wrongly mark line 1 as equivalent.
    source = "def foo\n  x > 0\nend # evilution:equivalent\n"
    mutation = double("Mutation", original_source: source, line: 1)

    expect(heuristic.match?(mutation)).to be false
  end
end
