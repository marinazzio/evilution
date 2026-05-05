# frozen_string_literal: true

require "spec_helper"
require "evilution/mcp/info_tool/request_parser"

RSpec.describe Evilution::MCP::InfoTool::RequestParser do
  describe ".parse_files" do
    it "returns empty files and ranges for empty input" do
      parsed = described_class.parse_files([])
      expect(parsed.files).to eq([])
      expect(parsed.ranges).to eq({})
    end

    it "extracts file without range" do
      parsed = described_class.parse_files(["lib/foo.rb"])
      expect(parsed.files).to eq(["lib/foo.rb"])
      expect(parsed.ranges).to eq({})
    end

    it "extracts file with single-line range" do
      parsed = described_class.parse_files(["lib/foo.rb:15"])
      expect(parsed.files).to eq(["lib/foo.rb"])
      expect(parsed.ranges).to eq("lib/foo.rb" => (15..15))
    end

    it "extracts file with closed range" do
      parsed = described_class.parse_files(["lib/foo.rb:15-30"])
      expect(parsed.ranges).to eq("lib/foo.rb" => (15..30))
    end

    it "extracts file with open-ended range" do
      parsed = described_class.parse_files(["lib/foo.rb:15-"])
      expect(parsed.ranges["lib/foo.rb"]).to eq(15..Float::INFINITY)
    end

    it "handles multiple files" do
      parsed = described_class.parse_files(["a.rb:1-3", "b.rb"])
      expect(parsed.files).to eq(["a.rb", "b.rb"])
      expect(parsed.ranges).to eq("a.rb" => (1..3))
    end
  end

  describe ".parse_line_range" do
    it "returns a single-line range for a plain integer" do
      expect(described_class.parse_line_range("7")).to eq(7..7)
    end

    it "returns a closed range for N-M" do
      expect(described_class.parse_line_range("5-10")).to eq(5..10)
    end

    it "returns an open-ended range for N-" do
      result = described_class.parse_line_range("5-")
      expect(result).to eq(5..Float::INFINITY)
    end

    it "raises ParseError on non-numeric input" do
      expect { described_class.parse_line_range("abc") }
        .to raise_error(Evilution::ParseError, 'invalid line range: "abc"')
    end

    it "raises ParseError on partial-numeric input" do
      expect { described_class.parse_line_range("1-x") }
        .to raise_error(Evilution::ParseError, 'invalid line range: "1-x"')
    end
  end
end
