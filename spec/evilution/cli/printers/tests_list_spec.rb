# frozen_string_literal: true

require "stringio"
require "evilution/cli/printers/tests_list"

RSpec.describe Evilution::CLI::Printers::TestsList do
  let(:io) { StringIO.new }

  describe "explicit mode" do
    it "prints each spec file indented" do
      described_class.new(mode: :explicit, specs: ["spec/a_spec.rb", "spec/b_spec.rb"]).render(io)
      expect(io.string).to include("  spec/a_spec.rb")
      expect(io.string).to include("  spec/b_spec.rb")
    end

    it "prints a plural summary when multiple spec files" do
      described_class.new(mode: :explicit, specs: ["spec/a_spec.rb", "spec/b_spec.rb"]).render(io)
      lines = io.string.split("\n")
      expect(lines).to include("2 spec files")
      expect(lines).to include("")
    end

    it "prints a singular summary when exactly one spec file" do
      described_class.new(mode: :explicit, specs: ["spec/a_spec.rb"]).render(io)
      lines = io.string.split("\n")
      expect(lines).to include("1 spec file")
    end
  end

  describe "resolved mode" do
    it "prints resolved specs with source paths in parens" do
      entries = [
        { source: "lib/a.rb", specs: ["spec/a_spec.rb"] },
        { source: "lib/b.rb", specs: ["spec/b_spec.rb"] }
      ]
      described_class.new(mode: :resolved, entries: entries).render(io)
      expect(io.string).to include("  spec/a_spec.rb  (lib/a.rb)")
      expect(io.string).to include("  spec/b_spec.rb  (lib/b.rb)")
    end

    it "prints one line per spec when a source resolves to several" do
      entries = [{ source: "lib/a.rb", specs: ["spec/a_spec.rb", "spec/a_edge_spec.rb"] }]
      described_class.new(mode: :resolved, entries: entries).render(io)
      expect(io.string).to include("  spec/a_spec.rb  (lib/a.rb)\n  spec/a_edge_spec.rb  (lib/a.rb)\n")
      expect(io.string).to include("1 source files, 2 spec files")
      expect(io.string).not_to include("no spec found")
    end

    it "prints (no spec found) when no spec resolves" do
      entries = [{ source: "lib/a.rb", specs: [] }]
      described_class.new(mode: :resolved, entries: entries).render(io)
      expect(io.string).to include("  lib/a.rb  (no spec found)")
    end

    it "prints summary with source file count and plural spec files" do
      entries = [
        { source: "lib/a.rb", specs: ["spec/a_spec.rb"] },
        { source: "lib/b.rb", specs: ["spec/b_spec.rb"] }
      ]
      described_class.new(mode: :resolved, entries: entries).render(io)
      expect(io.string).to include("2 source files, 2 spec files")
    end

    it "deduplicates specs in summary count" do
      entries = [
        { source: "lib/a.rb", specs: ["spec/shared_spec.rb"] },
        { source: "lib/b.rb", specs: ["spec/shared_spec.rb"] }
      ]
      described_class.new(mode: :resolved, entries: entries).render(io)
      expect(io.string).to include("2 source files, 1 spec file")
    end

    it "uses singular spec-file label when exactly one unique spec" do
      entries = [{ source: "lib/a.rb", specs: ["spec/a_spec.rb"] }]
      described_class.new(mode: :resolved, entries: entries).render(io)
      expect(io.string).to include("1 source files, 1 spec file")
    end

    it "excludes unresolved sources from the unique count" do
      entries = [
        { source: "lib/a.rb", specs: ["spec/a_spec.rb"] },
        { source: "lib/b.rb", specs: [] }
      ]
      described_class.new(mode: :resolved, entries: entries).render(io)
      expect(io.string).to include("2 source files, 1 spec file")
    end

    it "uses the exact singular spec-file label for one unique spec" do
      entries = [{ source: "lib/a.rb", specs: ["spec/a_spec.rb"] }]
      described_class.new(mode: :resolved, entries: entries).render(io)
      summary = io.string.split("\n").last
      expect(summary).to eq("1 source files, 1 spec file")
    end

    it "prints a blank separator line before the resolved summary" do
      entries = [{ source: "lib/a.rb", specs: ["spec/a_spec.rb"] }]
      described_class.new(mode: :resolved, entries: entries).render(io)
      lines = io.string.split("\n")
      expect(lines[lines.index("1 source files, 1 spec file") - 1]).to eq("")
    end
  end
end
