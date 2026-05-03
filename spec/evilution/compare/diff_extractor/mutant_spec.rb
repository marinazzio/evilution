# frozen_string_literal: true

require "evilution/compare/diff_extractor/mutant"

RSpec.describe Evilution::Compare::DiffExtractor::Mutant do
  subject(:extractor) { described_class.new }

  describe "#call" do
    it "keeps +/- payload lines and drops headers, hunk markers, and context" do
      diff = <<~DIFF
        --- Foo#bar
        +++ Foo#bar:evil:a1b2c
        @@ -1,3 +1,3 @@
         def bar
        -  a + b
        +  a - b
         end
      DIFF
      expect(extractor.call(diff)).to eq(minus: ["  a + b"], plus: ["  a - b"])
    end

    it "handles multi-line +/- blocks" do
      diff = <<~DIFF
        --- x
        +++ x
        @@ -1,4 +1,4 @@
        -one
        -two
        +alpha
        +beta
      DIFF
      expect(extractor.call(diff)).to eq(minus: %w[one two], plus: %w[alpha beta])
    end

    it "does not treat '---' / '+++' header lines as payload" do
      diff = "--- a\n+++ b\n@@ -1 +1 @@\n-x\n+y"
      expect(extractor.call(diff)).to eq(minus: ["x"], plus: ["y"])
    end

    it "returns empty arrays for empty input" do
      expect(extractor.call("")).to eq(minus: [], plus: [])
    end

    it "tolerates a nil diff" do
      expect(extractor.call(nil)).to eq(minus: [], plus: [])
    end

    it "preserves payload lines whose content starts with '--'" do
      diff = <<~DIFF
        --- a
        +++ b
        @@ -1 +1 @@
        ---flag
        +++flag
      DIFF
      expect(extractor.call(diff)).to eq(minus: ["--flag"], plus: ["++flag"])
    end
  end
end
