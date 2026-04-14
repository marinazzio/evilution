# frozen_string_literal: true

require "stringio"
require "json"
require "evilution/cli/printers/session_detail"

RSpec.describe Evilution::CLI::Printers::SessionDetail do
  let(:data) do
    {
      "timestamp" => "2026-04-01T12:00:00Z",
      "version" => "0.22.0",
      "git" => { "branch" => "main", "sha" => "abc123" },
      "summary" => {
        "score" => 0.85, "total" => 20, "killed" => 17, "survived" => 3,
        "timed_out" => 0, "errors" => 0, "duration" => 12.3
      },
      "survived" => [
        { "operator" => "LiteralInt", "file" => "lib/a.rb", "line" => 10,
          "subject" => "Foo#bar", "diff" => "- 1\n+ 2\n" }
      ]
    }
  end
  let(:io) { StringIO.new }

  describe "text format" do
    it "prints session metadata header" do
      described_class.new(data, format: :text).render(io)
      expect(io.string).to include("Session: 2026-04-01T12:00:00Z")
      expect(io.string).to include("Version: 0.22.0")
      expect(io.string).to include("Git:     main (abc123)")
    end

    it "skips git line when git data is missing" do
      data.delete("git")
      described_class.new(data, format: :text).render(io)
      expect(io.string).not_to include("Git:")
    end

    it "prints summary with formatted score" do
      described_class.new(data, format: :text).render(io)
      expect(io.string).to include("85.00%")
      expect(io.string).to include("Total: 20")
    end

    it "prints survived mutations section with diff" do
      described_class.new(data, format: :text).render(io)
      expect(io.string).to include("Survived mutations (1):")
      expect(io.string).to include("LiteralInt")
      expect(io.string).to include("lib/a.rb:10")
      expect(io.string).to include("Foo#bar")
      expect(io.string).to include("- 1")
      expect(io.string).to include("+ 2")
    end

    it "prints 'No survived mutations' when list is empty" do
      data["survived"] = []
      described_class.new(data, format: :text).render(io)
      expect(io.string).to include("No survived mutations")
    end
  end

  describe "json format" do
    it "emits pretty-generated JSON of the full data hash" do
      described_class.new(data, format: :json).render(io)
      parsed = JSON.parse(io.string)
      expect(parsed["timestamp"]).to eq("2026-04-01T12:00:00Z")
      expect(parsed.dig("summary", "score")).to eq(0.85)
      expect(parsed["survived"].length).to eq(1)
    end
  end
end
