# frozen_string_literal: true

require "stringio"
require "evilution/cli/commands/environment_show"
require "evilution/cli/parsed_args"

RSpec.describe Evilution::CLI::Commands::EnvironmentShow do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:parsed) { Evilution::CLI::ParsedArgs.new(command: :environment_show) }
  let(:config) { instance_double(Evilution::Config) }
  let(:printer) { instance_double(Evilution::CLI::Printers::Environment, render: nil) }

  before do
    allow(Evilution::Config).to receive(:new).and_return(config)
    allow(Evilution::CLI::Printers::Environment).to receive(:new).and_return(printer)
  end

  describe "when no config file exists on disk" do
    it "renders the environment with config_file: nil and returns 0" do
      allow(File).to receive(:exist?).and_return(false)

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(Evilution::CLI::Printers::Environment).to have_received(:new).with(config, config_file: nil)
      expect(printer).to have_received(:render).with(out)
      expect(result.exit_code).to eq(0)
    end
  end

  describe "when a config file is detected" do
    it "passes the detected config file path to the printer" do
      detected = Evilution::Config::CONFIG_FILES.first
      allow(File).to receive(:exist?).and_return(false)
      allow(File).to receive(:exist?).with(detected).and_return(true)

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(Evilution::CLI::Printers::Environment).to have_received(:new).with(config, config_file: detected)
      expect(printer).to have_received(:render).with(out)
      expect(result.exit_code).to eq(0)
    end
  end

  describe "when Config.new raises Evilution::ConfigError" do
    it "wraps the error into a Result with exit code 2" do
      allow(Evilution::Config).to receive(:new).and_raise(Evilution::ConfigError, "bad config")

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
    end
  end

  it "is registered with the dispatcher under :environment_show" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:environment_show)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:environment_show)).to eq(described_class)
  end
end
