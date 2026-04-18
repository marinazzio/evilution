# frozen_string_literal: true

require "evilution/mcp/mutate_tool"

RSpec.describe Evilution::MCP::MutateTool::OptionParser do
  describe ".parse_files" do
    it "returns plain files and empty ranges when no colon" do
      expect(described_class.parse_files(%w[lib/a.rb lib/b.rb])).to eq([%w[lib/a.rb lib/b.rb], {}])
    end

    it "extracts a single-line range" do
      files, ranges = described_class.parse_files(["lib/a.rb:42"])
      expect(files).to eq(["lib/a.rb"])
      expect(ranges).to eq("lib/a.rb" => (42..42))
    end

    it "extracts a bounded range" do
      _, ranges = described_class.parse_files(["lib/a.rb:10-20"])
      expect(ranges).to eq("lib/a.rb" => (10..20))
    end

    it "treats an open upper bound as infinity" do
      _, ranges = described_class.parse_files(["lib/a.rb:10-"])
      expect(ranges["lib/a.rb"]).to eq(10..Float::INFINITY)
    end

    it "raises ParseError for non-numeric range" do
      expect { described_class.parse_files(["lib/a.rb:abc"]) }.to raise_error(Evilution::ParseError, /invalid line range/)
    end
  end

  describe ".normalize_verbosity" do
    it "defaults blank/nil to summary" do
      expect(described_class.normalize_verbosity(nil)).to eq("summary")
      expect(described_class.normalize_verbosity("")).to eq("summary")
    end

    it "accepts the three documented values" do
      %w[full summary minimal].each do |v|
        expect(described_class.normalize_verbosity(v)).to eq(v)
      end
    end

    it "is case-insensitive and trims" do
      expect(described_class.normalize_verbosity(" MINIMAL ")).to eq("minimal")
    end

    it "raises ParseError for anything else" do
      expect { described_class.normalize_verbosity("loud") }.to raise_error(Evilution::ParseError, /invalid verbosity/)
    end
  end

  describe ".validate!" do
    it "does nothing for allowed keys" do
      expect { described_class.validate!(target: "Foo#bar", timeout: 5) }.not_to raise_error
    end

    it "raises ParseError listing unknown keys" do
      expect { described_class.validate!(bogus: 1, also_bogus: 2) }.to raise_error(Evilution::ParseError, /unknown parameters/)
    end
  end

  describe "constants" do
    it "exposes the passthrough and allowed key lists" do
      expect(described_class::PASSTHROUGH_KEYS).to include(
        :target, :timeout, :jobs, :fail_fast, :suggest_tests,
        :incremental, :integration, :isolation, :baseline, :save_session
      )
      expect(described_class::ALLOWED_OPT_KEYS).to include(:spec, :skip_config)
      expect(described_class::VALID_VERBOSITIES).to eq(%w[full summary minimal])
    end
  end
end
