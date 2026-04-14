# frozen_string_literal: true

require "json"
require "stringio"
require "evilution/cli/commands/session_diff"
require "evilution/cli/parsed_args"
require "evilution/session/store"
require "evilution/session/diff"

RSpec.describe Evilution::CLI::Commands::SessionDiff do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  let(:store) { instance_double(Evilution::Session::Store) }
  let(:diff) { instance_double(Evilution::Session::Diff) }
  let(:printer) { instance_double(Evilution::CLI::Printers::SessionDiff, render: nil) }
  let(:base_data) { { "version" => "0.13.0", "id" => "base" } }
  let(:head_data) { { "version" => "0.13.0", "id" => "head" } }
  let(:diff_result) { { added: [], removed: [] } }

  before do
    allow(Evilution::Session::Store).to receive(:new).and_return(store)
    allow(store).to receive(:load).with("base.json").and_return(base_data)
    allow(store).to receive(:load).with("head.json").and_return(head_data)
    allow(Evilution::Session::Diff).to receive(:new).and_return(diff)
    allow(diff).to receive(:call).and_return(diff_result)
    allow(Evilution::CLI::Printers::SessionDiff).to receive(:new).and_return(printer)
  end

  def parsed(files: [], options: {})
    Evilution::CLI::ParsedArgs.new(command: :session_diff, files: files, options: options)
  end

  describe "happy path" do
    it "loads both session files via Session::Store#load" do
      described_class.new(parsed(files: ["base.json", "head.json"]), stdout: out, stderr: err).call
      expect(store).to have_received(:load).with("base.json")
      expect(store).to have_received(:load).with("head.json")
    end

    it "invokes Session::Diff#call with base and head data" do
      described_class.new(parsed(files: ["base.json", "head.json"]), stdout: out, stderr: err).call
      expect(diff).to have_received(:call).with(base_data, head_data)
    end

    it "renders the diff result via SessionDiff printer with the format option" do
      described_class.new(
        parsed(files: ["base.json", "head.json"], options: { format: :json }),
        stdout: out, stderr: err
      ).call
      expect(Evilution::CLI::Printers::SessionDiff).to have_received(:new).with(diff_result, format: :json)
      expect(printer).to have_received(:render).with(out)
    end

    it "returns exit code 0" do
      result = described_class.new(parsed(files: ["base.json", "head.json"]), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(0)
    end
  end

  describe "wrong arg count" do
    it "wraps ConfigError into Result with exit 2 when no files" do
      result = described_class.new(parsed(files: []), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
      expect(result.error.message).to eq("two session file paths required")
    end

    it "wraps ConfigError into Result with exit 2 when only one file" do
      result = described_class.new(parsed(files: ["one.json"]), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
      expect(result.error.message).to eq("two session file paths required")
    end

    it "wraps ConfigError into Result with exit 2 when three files" do
      result = described_class.new(parsed(files: %w[a.json b.json c.json]), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
    end
  end

  describe "SystemCallError from store.load" do
    before do
      allow(store).to receive(:load).and_raise(Errno::ENOENT, "base.json")
    end

    it "wraps the error as Evilution::Error with exit 2" do
      result = described_class.new(parsed(files: ["base.json", "head.json"]), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::Error)
      expect(result.error.message).to include("No such file or directory")
    end
  end

  describe "JSON::ParserError from store.load" do
    before do
      allow(store).to receive(:load).and_raise(JSON::ParserError, "unexpected token")
    end

    it "wraps the error as Evilution::Error with prefixed message" do
      result = described_class.new(parsed(files: ["bad.json", "head.json"]), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::Error)
      expect(result.error.message).to eq("invalid session file: unexpected token")
    end
  end

  it "is registered with the dispatcher under :session_diff" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:session_diff)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:session_diff)).to eq(described_class)
  end
end
