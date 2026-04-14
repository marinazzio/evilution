# frozen_string_literal: true

require "stringio"
require "json"
require "evilution/cli/printers/session_list"

RSpec.describe Evilution::CLI::Printers::SessionList do
  let(:sessions) do
    [
      { timestamp: "2026-04-01T12:00:00Z", total: 10, killed: 8, survived: 2,
        score: 0.8, duration: 5.5, file: "a.json" },
      { timestamp: "2026-04-02T13:00:00Z", total: 20, killed: 15, survived: 5,
        score: 0.75, duration: 6.0, file: "b.json" }
    ]
  end
  let(:io) { StringIO.new }

  describe "text format" do
    before { described_class.new(sessions, format: :text).render(io) }

    it "prints a header with timestamp, totals, and score columns" do
      expect(io.string).to include("Timestamp")
      expect(io.string).to include("Total")
      expect(io.string).to include("Killed")
      expect(io.string).to include("Surv.")
      expect(io.string).to include("Score")
      expect(io.string).to include("Duration")
    end

    it "prints a separator line" do
      expect(io.string).to match(/^-+$/)
    end

    it "prints one row per session with formatted score and duration" do
      expect(io.string).to include("2026-04-01T12:00:00Z")
      expect(io.string).to include("2026-04-02T13:00:00Z")
      expect(io.string).to include("80.00%")
      expect(io.string).to include("75.00%")
      expect(io.string).to match(/5\.5s/)
      expect(io.string).to match(/6\.0s/)
    end
  end

  describe "json format" do
    before { described_class.new(sessions, format: :json).render(io) }

    it "emits an array of session hashes with string keys" do
      parsed = JSON.parse(io.string)
      expect(parsed.length).to eq(2)
      expect(parsed.first).to include(
        "timestamp" => "2026-04-01T12:00:00Z",
        "total" => 10,
        "killed" => 8,
        "survived" => 2,
        "score" => 0.8,
        "duration" => 5.5,
        "file" => "a.json"
      )
    end
  end

  describe "default format" do
    it "treats nil/unknown format as text" do
      described_class.new(sessions, format: nil).render(io)
      expect(io.string).to include("Timestamp")
    end
  end
end
