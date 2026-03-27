# frozen_string_literal: true

require "json"
require "tmpdir"
require "evilution/cli"
require "evilution/session/store"
require "support/cli_helpers"

RSpec.describe Evilution::CLI, "session list" do
  include CLIHelpers

  let(:results_dir) { Dir.mktmpdir("evilution-sessions") }

  after { FileUtils.rm_rf(results_dir) }

  def write_session(dir, filename, data)
    File.write(File.join(dir, filename), JSON.generate(data))
  end

  def session_data(timestamp:, total: 10, killed: 8, survived: 2, score: 0.8, duration: 5.0)
    {
      "timestamp" => timestamp,
      "summary" => {
        "total" => total,
        "killed" => killed,
        "survived" => survived,
        "score" => score,
        "duration" => duration
      }
    }
  end

  describe "session subcommand errors" do
    it "returns exit code 2 when no subcommand is given" do
      cli = described_class.new(["session"])
      result = nil
      capture_stderr { result = cli.call }
      expect(result).to eq(2)
    end

    it "prints error for missing subcommand" do
      cli = described_class.new(["session"])
      output = capture_stderr { cli.call }
      expect(output).to include("Missing session subcommand")
      expect(output).to include("list")
    end

    it "returns exit code 2 for unknown subcommand" do
      cli = described_class.new(%w[session bogus])
      result = nil
      capture_stderr { result = cli.call }
      expect(result).to eq(2)
    end

    it "prints error for unknown subcommand" do
      cli = described_class.new(%w[session bogus])
      output = capture_stderr { cli.call }
      expect(output).to include("Unknown session subcommand: bogus")
    end
  end

  describe "session list command" do
    it "returns exit code 0" do
      cli = described_class.new(["session", "list", "--results-dir", results_dir])
      result = nil
      capture_stdout { result = cli.call }
      expect(result).to eq(0)
    end

    it "outputs session entries with timestamp, total, killed, survived, score, and duration" do
      write_session(results_dir, "20260320T100000-aabb0000.json",
                    session_data(timestamp: "2026-03-20T10:00:00+00:00", total: 15, killed: 12,
                                 survived: 3, score: 0.8, duration: 4.5))

      cli = described_class.new(["session", "list", "--results-dir", results_dir])
      output = capture_stdout { cli.call }

      expect(output).to include("2026-03-20T10:00:00+00:00")
      expect(output).to include("15")
      expect(output).to include("12")
      expect(output).to include("3")
      expect(output).to include("80.00%")
      expect(output).to include("4.5")
    end

    it "outputs sessions in reverse chronological order" do
      write_session(results_dir, "20260320T100000-aabb0000.json",
                    session_data(timestamp: "2026-03-20T10:00:00+00:00"))
      write_session(results_dir, "20260321T100000-ccdd0000.json",
                    session_data(timestamp: "2026-03-21T10:00:00+00:00"))

      cli = described_class.new(["session", "list", "--results-dir", results_dir])
      output = capture_stdout { cli.call }

      idx_first = output.index("2026-03-21")
      idx_second = output.index("2026-03-20")
      expect(idx_first).to be < idx_second
    end

    it "outputs a message when no sessions exist" do
      cli = described_class.new(["session", "list", "--results-dir", results_dir])
      output = capture_stdout { cli.call }

      expect(output).to include("No sessions found")
    end

    it "respects --limit to show only the N most recent sessions" do
      write_session(results_dir, "20260320T100000-aabb0000.json",
                    session_data(timestamp: "2026-03-20T10:00:00+00:00"))
      write_session(results_dir, "20260321T100000-ccdd0000.json",
                    session_data(timestamp: "2026-03-21T10:00:00+00:00"))
      write_session(results_dir, "20260322T100000-eeff0000.json",
                    session_data(timestamp: "2026-03-22T10:00:00+00:00"))

      cli = described_class.new(["session", "list", "--results-dir", results_dir, "--limit", "2"])
      output = capture_stdout { cli.call }

      expect(output).to include("2026-03-22")
      expect(output).to include("2026-03-21")
      expect(output).not_to include("2026-03-20")
    end

    it "respects --since to filter sessions by date" do
      write_session(results_dir, "20260319T100000-aabb0000.json",
                    session_data(timestamp: "2026-03-19T10:00:00+00:00"))
      write_session(results_dir, "20260321T100000-ccdd0000.json",
                    session_data(timestamp: "2026-03-21T10:00:00+00:00"))

      cli = described_class.new(["session", "list", "--results-dir", results_dir, "--since", "2026-03-20"])
      output = capture_stdout { cli.call }

      expect(output).to include("2026-03-21")
      expect(output).not_to include("2026-03-19")
    end

    it "supports --format json to output JSON array" do
      write_session(results_dir, "20260320T100000-aabb0000.json",
                    session_data(timestamp: "2026-03-20T10:00:00+00:00", total: 10, killed: 9,
                                 survived: 1, score: 0.9, duration: 3.0))

      cli = described_class.new(["session", "list", "--results-dir", results_dir, "--format", "json"])
      output = capture_stdout { cli.call }
      parsed = JSON.parse(output)

      expect(parsed).to be_an(Array)
      expect(parsed.length).to eq(1)
      expect(parsed.first["total"]).to eq(10)
      expect(parsed.first["score"]).to eq(0.9)
    end

    it "returns exit code 2 for invalid --since date" do
      cli = described_class.new(["session", "list", "--results-dir", results_dir, "--since", "not-a-date"])
      result = nil
      capture_stderr { result = cli.call }
      expect(result).to eq(2)
    end

    it "prints error message for invalid --since date" do
      cli = described_class.new(["session", "list", "--results-dir", results_dir, "--since", "not-a-date"])
      output = capture_stderr { cli.call }
      expect(output).to include("invalid --since date")
    end

    it "skips sessions with missing summary structure" do
      write_session(results_dir, "20260320T100000-aabb0000.json",
                    session_data(timestamp: "2026-03-20T10:00:00+00:00"))
      File.write(File.join(results_dir, "20260321T100000-bad00000.json"), JSON.generate({ "no_summary" => true }))

      cli = described_class.new(["session", "list", "--results-dir", results_dir])
      output = capture_stdout { cli.call }

      expect(output).to include("2026-03-20")
      expect(output).not_to include("no_summary")
    end

    it "combines --limit and --since filters" do
      write_session(results_dir, "20260319T100000-aabb0000.json",
                    session_data(timestamp: "2026-03-19T10:00:00+00:00"))
      write_session(results_dir, "20260321T100000-ccdd0000.json",
                    session_data(timestamp: "2026-03-21T10:00:00+00:00"))
      write_session(results_dir, "20260322T100000-eeff0000.json",
                    session_data(timestamp: "2026-03-22T10:00:00+00:00"))
      write_session(results_dir, "20260323T100000-11220000.json",
                    session_data(timestamp: "2026-03-23T10:00:00+00:00"))

      cli = described_class.new(["session", "list", "--results-dir", results_dir,
                                 "--since", "2026-03-20", "--limit", "1"])
      output = capture_stdout { cli.call }

      expect(output).to include("2026-03-23")
      expect(output).not_to include("2026-03-22")
      expect(output).not_to include("2026-03-19")
    end
  end
end
