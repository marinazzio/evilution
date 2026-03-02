# frozen_string_literal: true

require "evilution/diff/parser"

RSpec.describe Evilution::Diff::Parser do
  subject(:parser) { described_class.new }

  describe "#parse" do
    it "extracts changed files and line ranges from git diff output" do
      diff_output = <<~DIFF
        diff --git a/lib/foo.rb b/lib/foo.rb
        index abc1234..def5678 100644
        --- a/lib/foo.rb
        +++ b/lib/foo.rb
        @@ -3,2 +3,3 @@ class Foo
           def bar
        +    x = 1
             y = 2
      DIFF

      allow(parser).to receive(:run_git_diff).and_return(diff_output)

      result = parser.parse("HEAD~1")

      expect(result).to eq([{ file: "lib/foo.rb", lines: [3..5] }])
    end

    it "handles multiple hunks in the same file" do
      diff_output = <<~DIFF
        diff --git a/lib/foo.rb b/lib/foo.rb
        index abc1234..def5678 100644
        --- a/lib/foo.rb
        +++ b/lib/foo.rb
        @@ -3,0 +3,1 @@ class Foo
        +  new_line
        @@ -10,0 +11,2 @@ def bar
        +  another
        +  line
      DIFF

      allow(parser).to receive(:run_git_diff).and_return(diff_output)

      result = parser.parse("HEAD~1")

      expect(result).to eq([{ file: "lib/foo.rb", lines: [3..3, 11..12] }])
    end

    it "handles multiple changed files" do
      diff_output = <<~DIFF
        diff --git a/lib/foo.rb b/lib/foo.rb
        index abc1234..def5678 100644
        --- a/lib/foo.rb
        +++ b/lib/foo.rb
        @@ -1,0 +1,1 @@
        +new_line
        diff --git a/lib/bar.rb b/lib/bar.rb
        index abc1234..def5678 100644
        --- a/lib/bar.rb
        +++ b/lib/bar.rb
        @@ -5,0 +5,1 @@
        +another
      DIFF

      allow(parser).to receive(:run_git_diff).and_return(diff_output)

      result = parser.parse("main")

      expect(result.size).to eq(2)
      expect(result).to include({ file: "lib/foo.rb", lines: [1..1] })
      expect(result).to include({ file: "lib/bar.rb", lines: [5..5] })
    end

    it "skips pure deletion hunks (count=0)" do
      diff_output = <<~DIFF
        diff --git a/lib/foo.rb b/lib/foo.rb
        index abc1234..def5678 100644
        --- a/lib/foo.rb
        +++ b/lib/foo.rb
        @@ -3,2 +3,0 @@ class Foo
        -  removed_line1
        -  removed_line2
      DIFF

      allow(parser).to receive(:run_git_diff).and_return(diff_output)

      result = parser.parse("HEAD~1")

      expect(result).to eq([])
    end

    it "returns an empty array when there are no changes" do
      allow(parser).to receive(:run_git_diff).and_return("")

      result = parser.parse("HEAD~1")

      expect(result).to eq([])
    end

    it "handles single-line additions (no count in hunk header)" do
      diff_output = <<~DIFF
        diff --git a/lib/foo.rb b/lib/foo.rb
        index abc1234..def5678 100644
        --- a/lib/foo.rb
        +++ b/lib/foo.rb
        @@ -3,0 +4 @@ class Foo
        +  new_line
      DIFF

      allow(parser).to receive(:run_git_diff).and_return(diff_output)

      result = parser.parse("HEAD~1")

      expect(result).to eq([{ file: "lib/foo.rb", lines: [4..4] }])
    end
  end
end
