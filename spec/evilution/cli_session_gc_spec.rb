# frozen_string_literal: true

require "json"
require "tmpdir"
require "evilution/cli"
require "evilution/session/store"
require "support/cli_helpers"

RSpec.describe Evilution::CLI, "session gc" do
  include CLIHelpers

  let(:results_dir) { Dir.mktmpdir("evilution-sessions") }
  let(:frozen_time) { Time.new(2026, 4, 1, 12, 0, 0) }

  before { allow(Time).to receive(:now).and_return(frozen_time) }
  after { FileUtils.rm_rf(results_dir) }

  describe "session gc command" do
    it "returns exit code 0" do
      cli = described_class.new(["session", "gc", "--results-dir", results_dir, "--older-than", "30d"])
      result = nil
      capture_stdout { result = cli.call }
      expect(result).to eq(0)
    end

    it "deletes sessions older than the specified duration" do
      File.write(File.join(results_dir, "20250101T000000-aaaa0000.json"), "{}")
      File.write(File.join(results_dir, "20260325T000000-bbbb0000.json"), "{}")

      cli = described_class.new(["session", "gc", "--results-dir", results_dir, "--older-than", "30d"])
      capture_stdout { cli.call }

      files = Dir.glob(File.join(results_dir, "*.json"))
      expect(files.length).to eq(1)
      expect(files.first).to include("20260325")
    end

    it "reports number of deleted sessions" do
      File.write(File.join(results_dir, "20250101T000000-aaaa0000.json"), "{}")
      File.write(File.join(results_dir, "20250201T000000-bbbb0000.json"), "{}")

      cli = described_class.new(["session", "gc", "--results-dir", results_dir, "--older-than", "30d"])
      output = capture_stdout { cli.call }

      expect(output).to include("Deleted 2 session")
    end

    it "reports when no sessions need cleanup" do
      cli = described_class.new(["session", "gc", "--results-dir", results_dir, "--older-than", "30d"])
      output = capture_stdout { cli.call }

      expect(output).to include("No sessions to delete")
    end

    it "returns exit code 2 when --older-than is missing" do
      cli = described_class.new(["session", "gc", "--results-dir", results_dir])
      result = nil
      capture_stderr { result = cli.call }
      expect(result).to eq(2)
    end

    it "prints error when --older-than is missing" do
      cli = described_class.new(["session", "gc", "--results-dir", results_dir])
      output = capture_stderr { cli.call }
      expect(output).to include("--older-than is required")
    end

    it "returns exit code 2 for invalid --older-than format" do
      cli = described_class.new(["session", "gc", "--results-dir", results_dir, "--older-than", "abc"])
      result = nil
      capture_stderr { result = cli.call }
      expect(result).to eq(2)
    end

    it "prints error for invalid --older-than format" do
      cli = described_class.new(["session", "gc", "--results-dir", results_dir, "--older-than", "abc"])
      output = capture_stderr { cli.call }
      expect(output).to include("invalid --older-than")
    end

    it "supports hours unit" do
      File.write(File.join(results_dir, "20250101T000000-aaaa0000.json"), "{}")

      cli = described_class.new(["session", "gc", "--results-dir", results_dir, "--older-than", "24h"])
      output = capture_stdout { cli.call }

      expect(output).to include("Deleted 1 session")
    end

    it "supports weeks unit" do
      File.write(File.join(results_dir, "20250101T000000-aaaa0000.json"), "{}")

      cli = described_class.new(["session", "gc", "--results-dir", results_dir, "--older-than", "1w"])
      output = capture_stdout { cli.call }

      expect(output).to include("Deleted 1 session")
    end
  end
end
