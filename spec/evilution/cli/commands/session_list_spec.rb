# frozen_string_literal: true

require "stringio"
require "evilution/cli/commands/session_list"
require "evilution/cli/parsed_args"
require "evilution/session/store"

RSpec.describe Evilution::CLI::Commands::SessionList do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  let(:store) { instance_double(Evilution::Session::Store, list: sessions) }
  let(:printer) { instance_double(Evilution::CLI::Printers::SessionList, render: nil) }
  let(:sessions) { [] }

  before do
    allow(Evilution::Session::Store).to receive(:new).and_return(store)
    allow(Evilution::CLI::Printers::SessionList).to receive(:new).and_return(printer)
  end

  def parsed(options = {})
    Evilution::CLI::ParsedArgs.new(command: :session_list, options: options)
  end

  describe "when no sessions exist" do
    let(:sessions) { [] }

    it "prints 'No sessions found' and returns exit 0" do
      result = described_class.new(parsed({}), stdout: out, stderr: err).call
      expect(out.string).to include("No sessions found")
      expect(result.exit_code).to eq(0)
      expect(Evilution::CLI::Printers::SessionList).not_to have_received(:new)
    end
  end

  describe "when sessions exist" do
    let(:sessions) do
      [
        { timestamp: "2026-03-21T10:00:00+00:00" },
        { timestamp: "2026-03-20T10:00:00+00:00" }
      ]
    end

    it "invokes printer with sessions and format" do
      described_class.new(parsed(format: :json), stdout: out, stderr: err).call
      expect(Evilution::CLI::Printers::SessionList).to have_received(:new).with(sessions, format: :json)
      expect(printer).to have_received(:render).with(out)
    end

    it "returns exit code 0" do
      result = described_class.new(parsed(format: :text), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(0)
    end
  end

  describe "with --since option" do
    let(:sessions) do
      [
        { timestamp: "2026-03-22T10:00:00+00:00" },
        { timestamp: "2026-03-19T10:00:00+00:00" },
        { timestamp: "not-a-timestamp" },
        { timestamp: nil }
      ]
    end

    it "filters out sessions before cutoff, invalid timestamps, and non-strings" do
      described_class.new(parsed(since: "2026-03-20"), stdout: out, stderr: err).call
      expect(Evilution::CLI::Printers::SessionList).to have_received(:new)
        .with([{ timestamp: "2026-03-22T10:00:00+00:00" }], format: nil)
    end
  end

  describe "with --limit option" do
    let(:sessions) do
      [
        { timestamp: "2026-03-22T10:00:00+00:00" },
        { timestamp: "2026-03-21T10:00:00+00:00" },
        { timestamp: "2026-03-20T10:00:00+00:00" }
      ]
    end

    it "truncates to the first N sessions" do
      described_class.new(parsed(limit: 2), stdout: out, stderr: err).call
      expect(Evilution::CLI::Printers::SessionList).to have_received(:new)
        .with(sessions.first(2), format: nil)
    end
  end

  describe "with invalid --since date" do
    let(:sessions) { [{ timestamp: "2026-03-22T10:00:00+00:00" }] }

    it "wraps ConfigError into Result with exit 2" do
      result = described_class.new(parsed(since: "not-a-date"), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
      expect(result.error.message).to include("invalid --since date")
    end
  end

  describe "with --results-dir option" do
    it "passes results_dir through to Session::Store.new" do
      described_class.new(parsed(results_dir: "/tmp/custom"), stdout: out, stderr: err).call
      expect(Evilution::Session::Store).to have_received(:new).with(results_dir: "/tmp/custom")
    end

    it "omits results_dir when not provided" do
      described_class.new(parsed({}), stdout: out, stderr: err).call
      expect(Evilution::Session::Store).to have_received(:new).with(no_args)
    end
  end

  it "is registered with the dispatcher under :session_list" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:session_list)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:session_list)).to eq(described_class)
  end
end
