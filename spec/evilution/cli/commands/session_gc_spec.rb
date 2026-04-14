# frozen_string_literal: true

require "stringio"
require "evilution/cli/commands/session_gc"
require "evilution/cli/parsed_args"
require "evilution/session/store"

RSpec.describe Evilution::CLI::Commands::SessionGc do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:store) { instance_double(Evilution::Session::Store) }

  before do
    allow(Evilution::Session::Store).to receive(:new).and_return(store)
    allow(store).to receive(:gc).and_return([])
  end

  def parsed(options: {})
    Evilution::CLI::ParsedArgs.new(command: :session_gc, options: options)
  end

  describe "missing --older-than" do
    it "wraps ConfigError into Result with exit 2" do
      result = described_class.new(parsed(options: {}), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
      expect(result.error.message).to eq("--older-than is required for session gc")
    end
  end

  describe "invalid duration formats" do
    %w[foo 30x bar 10 d30].each do |bad|
      it "raises ConfigError for #{bad.inspect}" do
        result = described_class.new(parsed(options: { older_than: bad }), stdout: out, stderr: err).call
        expect(result.exit_code).to eq(2)
        expect(result.error).to be_a(Evilution::ConfigError)
        expect(result.error.message).to eq(
          "invalid --older-than format: #{bad.inspect}. Use Nd, Nh, or Nw (e.g., 30d)"
        )
      end
    end

    it "raises ConfigError for empty string" do
      result = described_class.new(parsed(options: { older_than: "" }), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
      expect(result.error.message).to include("invalid --older-than format")
    end
  end

  describe "valid durations" do
    it "passes a cutoff ~30 days ago for 30d" do
      now = Time.now
      described_class.new(parsed(options: { older_than: "30d" }), stdout: out, stderr: err).call
      expect(store).to have_received(:gc) do |older_than:|
        expect(older_than).to be_within(5).of(now - (30 * 86_400))
      end
    end

    it "passes a cutoff ~3 hours ago for 3h" do
      now = Time.now
      described_class.new(parsed(options: { older_than: "3h" }), stdout: out, stderr: err).call
      expect(store).to have_received(:gc) do |older_than:|
        expect(older_than).to be_within(5).of(now - (3 * 3600))
      end
    end

    it "passes a cutoff ~2 weeks ago for 2w" do
      now = Time.now
      described_class.new(parsed(options: { older_than: "2w" }), stdout: out, stderr: err).call
      expect(store).to have_received(:gc) do |older_than:|
        expect(older_than).to be_within(5).of(now - (2 * 604_800))
      end
    end
  end

  describe "results-dir option" do
    it "passes --results-dir to Session::Store.new" do
      described_class.new(
        parsed(options: { older_than: "1d", results_dir: "/tmp/results" }),
        stdout: out, stderr: err
      ).call
      expect(Evilution::Session::Store).to have_received(:new).with(results_dir: "/tmp/results")
    end

    it "constructs Session::Store with no kwargs when results_dir omitted" do
      described_class.new(parsed(options: { older_than: "1d" }), stdout: out, stderr: err).call
      expect(Evilution::Session::Store).to have_received(:new).with(no_args)
    end
  end

  describe "output messages" do
    it "prints 'No sessions to delete' when nothing was deleted" do
      allow(store).to receive(:gc).and_return([])
      result = described_class.new(parsed(options: { older_than: "1d" }), stdout: out, stderr: err).call
      expect(out.string).to eq("No sessions to delete\n")
      expect(result.exit_code).to eq(0)
    end

    it "prints singular when one session deleted" do
      allow(store).to receive(:gc).and_return(["a"])
      described_class.new(parsed(options: { older_than: "1d" }), stdout: out, stderr: err).call
      expect(out.string).to eq("Deleted 1 session\n")
    end

    it "prints plural when two sessions deleted" do
      allow(store).to receive(:gc).and_return(%w[a b])
      described_class.new(parsed(options: { older_than: "1d" }), stdout: out, stderr: err).call
      expect(out.string).to eq("Deleted 2 sessions\n")
    end

    it "prints plural when three sessions deleted" do
      allow(store).to receive(:gc).and_return(%w[a b c])
      described_class.new(parsed(options: { older_than: "1d" }), stdout: out, stderr: err).call
      expect(out.string).to eq("Deleted 3 sessions\n")
    end
  end

  it "is registered with the dispatcher under :session_gc" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:session_gc)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:session_gc)).to eq(described_class)
  end
end
