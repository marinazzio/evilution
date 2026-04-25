# frozen_string_literal: true

require "spec_helper"
require "evilution/reporter/cli/item_formatters/coverage_gap"

RSpec.describe Evilution::Reporter::CLI::ItemFormatters::CoverageGap do
  describe "#format" do
    let(:mutation) { double("mutation", unified_diff: "-old\n+new") }
    let(:result) { double("result", mutation: mutation) }

    it "formats a single-mutation gap with operator name and location" do
      gap = double(
        "gap",
        single?: true,
        primary_operator: "binary_swap",
        file_path: "lib/foo.rb",
        line: 42,
        subject_name: "Foo#bar",
        mutation_results: [result],
        primary_diff: "-old\n+new"
      )
      out = described_class.new.format(gap)
      expect(out).to eq("  binary_swap: lib/foo.rb:42 (Foo#bar)\n    -old\n    +new")
    end

    it "formats a multi-mutation gap with operator list and count" do
      gap = double(
        "gap",
        single?: false,
        operator_names: %w[binary_swap literal_replace],
        file_path: "lib/foo.rb",
        line: 42,
        subject_name: "Foo#bar",
        count: 2,
        mutation_results: [result],
        primary_diff: "-old\n+new"
      )
      out = described_class.new.format(gap)
      expect(out).to eq("  lib/foo.rb:42 (Foo#bar) [2 mutations: binary_swap, literal_replace]\n    -old\n    +new")
    end

    it "falls back to primary_diff when first result has no unified_diff" do
      no_diff_mutation = double("mutation", unified_diff: nil)
      no_diff_result = double("result", mutation: no_diff_mutation)
      gap = double(
        "gap",
        single?: true,
        primary_operator: "x",
        file_path: "f",
        line: 1,
        subject_name: "S",
        mutation_results: [no_diff_result],
        primary_diff: "fallback-diff"
      )
      out = described_class.new.format(gap)
      expect(out).to include("fallback-diff")
    end
  end
end
