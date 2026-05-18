# frozen_string_literal: true

require "evilution/compare/fingerprint"
require "evilution/compare/diff_extractor/evilution"
require "evilution/compare/diff_extractor/mutant"
require "evilution/compare/line_normalizer"

RSpec.describe Evilution::Compare::Fingerprint do
  let(:evilution_extractor) { Evilution::Compare::DiffExtractor::Evilution.new }
  let(:mutant_extractor) { Evilution::Compare::DiffExtractor::Mutant.new }
  let(:normalizer) { Evilution::Compare::LineNormalizer.new }

  describe "#call" do
    let(:fp) do
      described_class.new(extractor: evilution_extractor, normalizer: normalizer)
    end

    it "returns a hex SHA256 string" do
      result = fp.call(diff: "- a + b\n+ a - b", file_path: "lib/foo.rb", line: 42)
      expect(result).to match(/\A[0-9a-f]{64}\z/)
    end

    it "is deterministic for identical inputs" do
      a = fp.call(diff: "- a + b\n+ a - b", file_path: "lib/foo.rb", line: 42)
      b = fp.call(diff: "- a + b\n+ a - b", file_path: "lib/foo.rb", line: 42)
      expect(a).to eq(b)
    end

    it "differs for different file paths" do
      a = fp.call(diff: "- a + b\n+ a - b", file_path: "lib/foo.rb", line: 42)
      b = fp.call(diff: "- a + b\n+ a - b", file_path: "lib/bar.rb", line: 42)
      expect(a).not_to eq(b)
    end

    it "differs for different lines" do
      a = fp.call(diff: "- a + b\n+ a - b", file_path: "lib/foo.rb", line: 42)
      b = fp.call(diff: "- a + b\n+ a - b", file_path: "lib/foo.rb", line: 43)
      expect(a).not_to eq(b)
    end

    it "normalizes whitespace within each diff line before hashing" do
      raw = fp.call(diff: "-   a    +   b\n+   a   -   b", file_path: "f", line: 1)
      clean = fp.call(diff: "- a + b\n+ a - b", file_path: "f", line: 1)
      expect(raw).to eq(clean)
    end

    it "differs when only the minus (removed) lines differ" do
      a = fp.call(diff: "- aaa\n+ same", file_path: "f", line: 1)
      b = fp.call(diff: "- bbb\n+ same", file_path: "f", line: 1)
      expect(a).not_to eq(b)
    end

    it "differs when only the plus (added) lines differ" do
      a = fp.call(diff: "- same\n+ ppp", file_path: "f", line: 1)
      b = fp.call(diff: "- same\n+ qqq", file_path: "f", line: 1)
      expect(a).not_to eq(b)
    end

    it "produces matching fingerprints across evilution and mutant extractors for equivalent diffs" do
      mutant_fp = described_class.new(extractor: mutant_extractor, normalizer: normalizer)
      mutant_diff = "--- x\n+++ x\n@@ -1 +1 @@\n-a + b\n+a - b\n"
      evilution_diff = "- a + b\n+ a - b"

      expect(mutant_fp.call(diff: mutant_diff, file_path: "f", line: 1))
        .to eq(fp.call(diff: evilution_diff, file_path: "f", line: 1))
    end
  end
end
