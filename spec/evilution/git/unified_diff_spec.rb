# frozen_string_literal: true

require "evilution/git/unified_diff"

RSpec.describe Evilution::Git::UnifiedDiff do
  def lines(*ranges)
    Evilution::LineSet.new(ranges)
  end

  def file_diff(path, *hunks, old_path: path)
    ["diff --git a/#{old_path} b/#{path}", "index 1..2 100644", "--- a/#{old_path}", "+++ #{path}", *hunks].join("\n")
  end

  it "reads the new-file lines of each hunk" do
    output = file_diff("b/lib/a.rb", "@@ -3 +3 @@", "-x", "+y", "@@ -8,0 +9,2 @@", "+p", "+q")

    expect(described_class.parse(output)).to eq("lib/a.rb" => lines(3..3, 9..10))
  end

  it "reads each file of the diff apart" do
    output = [file_diff("b/lib/a.rb", "@@ -1 +1 @@", "-x", "+y"), file_diff("b/lib/b.rb", "@@ -2 +2,3 @@", "-x", "+y")].join("\n")

    expect(described_class.parse(output)).to eq("lib/a.rb" => lines(1..1), "lib/b.rb" => lines(2..4))
  end

  it "counts the lines either side of a hunk that only deletes" do
    expect(described_class.parse(file_diff("b/lib/a.rb", "@@ -5,2 +4,0 @@", "-x", "-y")))
      .to eq("lib/a.rb" => lines(4..5))
  end

  it "counts the first line when the hunk deletes the first lines" do
    expect(described_class.parse(file_diff("b/lib/a.rb", "@@ -1,2 +0,0 @@", "-x", "-y")))
      .to eq("lib/a.rb" => lines(1..1))
  end

  it "reads an added line that looks like a header as content" do
    output = file_diff("b/lib/a.rb", "@@ -1,0 +2,2 @@", "+++ b/lib/evil.rb", "+-- a/lib/evil.rb")

    expect(described_class.parse(output)).to eq("lib/a.rb" => lines(2..3))
  end

  it "reads the hunks after an added line that looks like a file header for the same file" do
    output = file_diff("b/lib/a.rb", "@@ -1,0 +2 @@", "+++ b/lib/evil.rb", "@@ -5 +6 @@", "-x", "+y")

    expect(described_class.parse(output)).to eq("lib/a.rb" => lines(2..2, 6..6))
  end

  it "ignores hunks before any file header" do
    expect(described_class.parse("@@ -1 +1 @@\n-x\n+y")).to eq({})
  end

  it "does not give a file without a +++ line the previous file's name" do
    output = [file_diff("b/lib/a.rb", "@@ -1 +1 @@"), "diff --git a/lib/b.rb b/lib/b.rb", "@@ -9 +9 @@"].join("\n")

    expect(described_class.parse(output)).to eq("lib/a.rb" => lines(1..1))
  end

  it "unquotes every C escape git writes in a path" do
    output = file_diff('"b/lib/\\a\\b\\f\\n\\r\\v.rb"', "@@ -1 +1 @@")

    expect(described_class.parse(output)).to eq("lib/\a\b\f\n\r\v.rb" => lines(1..1))
  end

  it "reads a path holding a space, which git ends in a tab" do
    expect(described_class.parse(file_diff("b/lib/a b.rb\t", "@@ -1 +1 @@")))
      .to eq("lib/a b.rb" => lines(1..1))
  end

  it "unquotes a C-quoted path, octal escapes as UTF-8 bytes" do
    output = file_diff('"b/lib/q\\"t\\tx\\\\\\303\\274.rb"', "@@ -1 +1 @@")

    expect(described_class.parse(output)).to eq("lib/q\"t\tx\\ü.rb" => lines(1..1))
  end

  it "leaves out a file without hunks, as a binary or rename-only change has" do
    output = ["diff --git a/lib/a.bin b/lib/a.bin", "index 1..2 100644", "Binary files a/lib/a.bin and b/lib/a.bin differ"]

    expect(described_class.parse(output.join("\n"))).to eq({})
  end

  it "reads nothing from empty output" do
    expect(described_class.parse("")).to eq({})
  end
end
