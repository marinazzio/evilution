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
end
