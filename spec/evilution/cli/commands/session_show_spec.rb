# frozen_string_literal: true

require "json"
require "stringio"
require "evilution/cli/commands/session_show"
require "evilution/cli/parsed_args"
require "evilution/session/store"

RSpec.describe Evilution::CLI::Commands::SessionShow do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  let(:store) { instance_double(Evilution::Session::Store) }
  let(:printer) { instance_double(Evilution::CLI::Printers::SessionDetail, render: nil) }
  let(:data) { { "version" => "0.13.0" } }

  before do
    allow(Evilution::Session::Store).to receive(:new).and_return(store)
    allow(store).to receive(:load).and_return(data)
    allow(Evilution::CLI::Printers::SessionDetail).to receive(:new).and_return(printer)
  end

  def parsed(files: [], options: {})
    Evilution::CLI::ParsedArgs.new(command: :session_show, files: files, options: options)
  end

  describe "happy path" do
    it "passes @files.first to Session::Store#load" do
      described_class.new(parsed(files: ["path/to/session.json"]), stdout: out, stderr: err).call
      expect(store).to have_received(:load).with("path/to/session.json")
    end

    it "renders data via the SessionDetail printer with the format option" do
      described_class.new(parsed(files: ["path.json"], options: { format: :json }), stdout: out, stderr: err).call
      expect(Evilution::CLI::Printers::SessionDetail).to have_received(:new).with(data, format: :json)
      expect(printer).to have_received(:render).with(out)
    end

    it "returns exit code 0" do
      result = described_class.new(parsed(files: ["path.json"]), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(0)
    end
  end

  describe "missing path" do
    it "wraps ConfigError into Result with exit 2" do
      result = described_class.new(parsed(files: []), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
      expect(result.error.message).to eq("session file path required")
    end
  end

  describe "JSON::ParserError from store.load" do
    before do
      allow(store).to receive(:load).and_raise(JSON::ParserError, "unexpected token")
    end

    it "wraps the error as Evilution::Error with prefixed message" do
      result = described_class.new(parsed(files: ["bad.json"]), stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::Error)
      expect(result.error.message).to eq("invalid session file: unexpected token")
    end
  end

  it "is registered with the dispatcher under :session_show" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:session_show)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:session_show)).to eq(described_class)
  end
end
