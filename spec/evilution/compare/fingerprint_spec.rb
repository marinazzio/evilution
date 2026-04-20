# frozen_string_literal: true

require "evilution/compare/fingerprint"

RSpec.describe Evilution::Compare::Fingerprint do
  describe ".extract_from_evilution_diff" do
    it "splits into minus and plus payloads, dropping markers" do
      diff = "- a + b\n+ a - b"
      result = described_class.extract_from_evilution_diff(diff)
      expect(result).to eq(minus: ["a + b"], plus: ["a - b"])
    end

    it "handles multi-line +/- blocks" do
      diff = "- a\n- b\n+ x\n+ y"
      expect(described_class.extract_from_evilution_diff(diff))
        .to eq(minus: %w[a b], plus: %w[x y])
    end

    it "returns empty arrays for an empty diff" do
      expect(described_class.extract_from_evilution_diff(""))
        .to eq(minus: [], plus: [])
    end

    it "ignores lines that lack the '- ' / '+ ' marker" do
      diff = "- a\nrandom\n+ b"
      expect(described_class.extract_from_evilution_diff(diff))
        .to eq(minus: ["a"], plus: ["b"])
    end
  end

  describe ".extract_from_mutant_diff" do
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
      expect(described_class.extract_from_mutant_diff(diff))
        .to eq(minus: ["  a + b"], plus: ["  a - b"])
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
      expect(described_class.extract_from_mutant_diff(diff))
        .to eq(minus: %w[one two], plus: %w[alpha beta])
    end

    it "does not treat '---' / '+++' header lines as payload" do
      diff = "--- a\n+++ b\n@@ -1 +1 @@\n-x\n+y"
      expect(described_class.extract_from_mutant_diff(diff))
        .to eq(minus: ["x"], plus: ["y"])
    end

    it "returns empty arrays for empty input" do
      expect(described_class.extract_from_mutant_diff(""))
        .to eq(minus: [], plus: [])
    end
  end

  describe ".normalize_line" do
    it "strips leading and trailing whitespace" do
      expect(described_class.normalize_line("  a + b  ")).to eq("a + b")
    end

    it "collapses runs of internal whitespace to a single space" do
      expect(described_class.normalize_line("a   +   b")).to eq("a + b")
    end

    it "preserves whitespace inside double-quoted strings" do
      expect(described_class.normalize_line('say("hi  there")')).to eq('say("hi  there")')
    end

    it "preserves whitespace inside single-quoted strings" do
      expect(described_class.normalize_line("say('hi  there')")).to eq("say('hi  there')")
    end

    it "handles escaped quotes inside strings" do
      expect(described_class.normalize_line('a = "he said \"hi  there\""'))
        .to eq('a = "he said \"hi  there\""')
    end

    it "collapses whitespace between literals but preserves within them" do
      expect(described_class.normalize_line('"a  b"   +   "c  d"'))
        .to eq('"a  b" + "c  d"')
    end

    it "is idempotent" do
      once = described_class.normalize_line("  a   +  b  ")
      expect(described_class.normalize_line(once)).to eq(once)
    end
  end

  describe ".compute" do
    let(:body) { { minus: ["a + b"], plus: ["a - b"] } }

    it "returns a hex SHA256 string" do
      fp = described_class.compute(file_path: "lib/foo.rb", line: 42, body: body)
      expect(fp).to match(/\A[0-9a-f]{64}\z/)
    end

    it "is deterministic" do
      fp1 = described_class.compute(file_path: "lib/foo.rb", line: 42, body: body)
      fp2 = described_class.compute(file_path: "lib/foo.rb", line: 42, body: body)
      expect(fp1).to eq(fp2)
    end

    it "differs for different file paths" do
      fp1 = described_class.compute(file_path: "lib/foo.rb", line: 42, body: body)
      fp2 = described_class.compute(file_path: "lib/bar.rb", line: 42, body: body)
      expect(fp1).not_to eq(fp2)
    end

    it "differs for different lines" do
      fp1 = described_class.compute(file_path: "lib/foo.rb", line: 42, body: body)
      fp2 = described_class.compute(file_path: "lib/foo.rb", line: 43, body: body)
      expect(fp1).not_to eq(fp2)
    end

    it "normalizes each body line before hashing" do
      raw   = { minus: ["  a    +   b  "], plus: ["a - b"] }
      clean = { minus: ["a + b"], plus: ["a - b"] }
      expect(described_class.compute(file_path: "f", line: 1, body: raw))
        .to eq(described_class.compute(file_path: "f", line: 1, body: clean))
    end
  end
end
