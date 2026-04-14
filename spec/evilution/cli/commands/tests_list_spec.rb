# frozen_string_literal: true

require "stringio"
require "evilution/cli/commands/tests_list"
require "evilution/cli/parsed_args"

RSpec.describe Evilution::CLI::Commands::TestsList do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:parsed) { Evilution::CLI::ParsedArgs.new(command: :tests_list, files: ["lib/a.rb"]) }
  let(:printer) { instance_double(Evilution::CLI::Printers::TestsList, render: nil) }

  describe "when config.spec_files is non-empty" do
    it "renders the explicit printer and returns 0" do
      config = instance_double(
        Evilution::Config,
        spec_files: ["spec/a_spec.rb"],
        target_files: ["lib/a.rb"]
      )
      allow(Evilution::Config).to receive(:new).and_return(config)
      allow(Evilution::CLI::Printers::TestsList).to receive(:new).and_return(printer)

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(Evilution::CLI::Printers::TestsList).to have_received(:new).with(
        mode: :explicit,
        specs: ["spec/a_spec.rb"]
      )
      expect(printer).to have_received(:render).with(out)
      expect(result.exit_code).to eq(0)
    end
  end

  describe "when no source files are resolved" do
    it "prints 'No source files found' and returns 0" do
      config = instance_double(
        Evilution::Config,
        spec_files: [],
        target_files: []
      )
      allow(Evilution::Config).to receive(:new).and_return(config)
      changed_files = instance_double(Evilution::Git::ChangedFiles, call: [])
      allow(Evilution::Git::ChangedFiles).to receive(:new).and_return(changed_files)

      parsed_no_files = Evilution::CLI::ParsedArgs.new(command: :tests_list)
      result = described_class.new(parsed_no_files, stdout: out, stderr: err).call

      expect(out.string).to include("No source files found")
      expect(result.exit_code).to eq(0)
    end
  end

  describe "when source files resolve via target_files" do
    it "calls SpecResolver per source and renders the resolved printer" do
      config = instance_double(
        Evilution::Config,
        spec_files: [],
        target_files: ["lib/a.rb", "lib/b.rb"]
      )
      allow(Evilution::Config).to receive(:new).and_return(config)
      resolver = instance_double(Evilution::SpecResolver)
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
      allow(resolver).to receive(:call).with("lib/a.rb").and_return("spec/a_spec.rb")
      allow(resolver).to receive(:call).with("lib/b.rb").and_return("spec/b_spec.rb")
      allow(Evilution::CLI::Printers::TestsList).to receive(:new).and_return(printer)

      parsed_files = Evilution::CLI::ParsedArgs.new(command: :tests_list, files: ["lib/a.rb", "lib/b.rb"])
      result = described_class.new(parsed_files, stdout: out, stderr: err).call

      expect(resolver).to have_received(:call).with("lib/a.rb")
      expect(resolver).to have_received(:call).with("lib/b.rb")
      expect(Evilution::CLI::Printers::TestsList).to have_received(:new).with(
        mode: :resolved,
        entries: [
          { source: "lib/a.rb", spec: "spec/a_spec.rb" },
          { source: "lib/b.rb", spec: "spec/b_spec.rb" }
        ]
      )
      expect(printer).to have_received(:render).with(out)
      expect(result.exit_code).to eq(0)
    end
  end

  describe "when target_files is empty" do
    it "falls through to Git::ChangedFiles" do
      config = instance_double(
        Evilution::Config,
        spec_files: [],
        target_files: []
      )
      allow(Evilution::Config).to receive(:new).and_return(config)
      changed_files = instance_double(Evilution::Git::ChangedFiles, call: ["lib/c.rb"])
      allow(Evilution::Git::ChangedFiles).to receive(:new).and_return(changed_files)
      resolver = instance_double(Evilution::SpecResolver, call: "spec/c_spec.rb")
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
      allow(Evilution::CLI::Printers::TestsList).to receive(:new).and_return(printer)

      parsed_no_files = Evilution::CLI::ParsedArgs.new(command: :tests_list)
      result = described_class.new(parsed_no_files, stdout: out, stderr: err).call

      expect(changed_files).to have_received(:call)
      expect(resolver).to have_received(:call).with("lib/c.rb")
      expect(Evilution::CLI::Printers::TestsList).to have_received(:new).with(
        mode: :resolved,
        entries: [{ source: "lib/c.rb", spec: "spec/c_spec.rb" }]
      )
      expect(result.exit_code).to eq(0)
    end

    it "treats Git::ChangedFiles raising Evilution::Error as empty" do
      config = instance_double(
        Evilution::Config,
        spec_files: [],
        target_files: []
      )
      allow(Evilution::Config).to receive(:new).and_return(config)
      changed_files = instance_double(Evilution::Git::ChangedFiles)
      allow(Evilution::Git::ChangedFiles).to receive(:new).and_return(changed_files)
      allow(changed_files).to receive(:call).and_raise(Evilution::Error, "git exploded")

      parsed_no_files = Evilution::CLI::ParsedArgs.new(command: :tests_list)
      result = described_class.new(parsed_no_files, stdout: out, stderr: err).call

      expect(out.string).to include("No source files found")
      expect(result.exit_code).to eq(0)
    end
  end

  describe "when Config.new raises Evilution::Error" do
    it "wraps the error into a Result with exit code 2" do
      allow(Evilution::Config).to receive(:new).and_raise(Evilution::ConfigError, "bad config")

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
    end
  end

  it "is registered with the dispatcher under :tests_list" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:tests_list)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:tests_list)).to eq(described_class)
  end
end
