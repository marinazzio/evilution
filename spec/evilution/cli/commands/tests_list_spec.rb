# frozen_string_literal: true

require "fileutils"
require "stringio"
require "tmpdir"
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

    it "does not run the resolver or the resolved printer when there are no source files" do
      config = instance_double(
        Evilution::Config,
        spec_files: [],
        target_files: []
      )
      allow(Evilution::Config).to receive(:new).and_return(config)
      changed_files = instance_double(Evilution::Git::ChangedFiles, call: [])
      allow(Evilution::Git::ChangedFiles).to receive(:new).and_return(changed_files)
      allow(Evilution::SpecResolver).to receive(:new)
      allow(Evilution::CLI::Printers::TestsList).to receive(:new)

      parsed_no_files = Evilution::CLI::ParsedArgs.new(command: :tests_list)
      described_class.new(parsed_no_files, stdout: out, stderr: err).call

      expect(Evilution::SpecResolver).not_to have_received(:new)
      expect(Evilution::CLI::Printers::TestsList).not_to have_received(:new)
    end
  end

  # End to end against a real project layout: `tests list` must resolve the
  # same files `run` would, because both go through Config#spec_selector
  # (integration-aware resolver + spec_mappings + spec_pattern). GH #1596.
  describe "parity with run's spec selection" do
    def list_in_project(files, options)
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          files.each do |path|
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, "")
          end
          parsed_args = Evilution::CLI::ParsedArgs.new(
            command: :tests_list, files: [files.first], options: options.merge(skip_config_file: true)
          )
          described_class.new(parsed_args, stdout: out, stderr: err).call
        end
      end
      out.string
    end

    it "resolves test/*_test.rb when integration is :minitest" do
      output = list_in_project(%w[app/models/user.rb test/models/user_test.rb], integration: :minitest)

      expect(output).to include("test/models/user_test.rb  (app/models/user.rb)")
      expect(output).not_to include("no spec found")
    end

    it "resolves test/*_test.rb when integration is :test_unit" do
      output = list_in_project(%w[lib/parser.rb test/parser_test.rb], integration: :test_unit)

      expect(output).to include("test/parser_test.rb  (lib/parser.rb)")
    end

    it "keeps the spec/*_spec.rb layout when integration is :rspec" do
      output = list_in_project(%w[lib/parser.rb spec/parser_spec.rb], integration: :rspec)

      expect(output).to include("spec/parser_spec.rb  (lib/parser.rb)")
    end

    it "honours spec_mappings" do
      output = list_in_project(
        %w[app/controllers/games_controller.rb spec/requests/games_overlay_spec.rb],
        spec_mappings: { "app/controllers/games_controller.rb" => ["spec/requests/games_overlay_spec.rb"] }
      )

      expect(output).to include("spec/requests/games_overlay_spec.rb  (app/controllers/games_controller.rb)")
    end

    it "lists every spec file a mapping resolves to" do
      output = list_in_project(
        %w[lib/parser.rb spec/parser_spec.rb spec/parser_edge_spec.rb],
        spec_mappings: { "lib/parser.rb" => %w[spec/parser_spec.rb spec/parser_edge_spec.rb] }
      )

      expect(output).to include("spec/parser_spec.rb  (lib/parser.rb)", "spec/parser_edge_spec.rb  (lib/parser.rb)")
      expect(output).to include("1 source files, 2 spec files")
    end
  end

  describe "when source files resolve via target_files" do
    it "resolves each source through config.spec_selector and renders the resolved printer" do
      selector = instance_double(Evilution::SpecSelector)
      allow(selector).to receive(:call).with("lib/a.rb").and_return(["spec/a_spec.rb"])
      allow(selector).to receive(:call).with("lib/b.rb").and_return(nil)
      config = instance_double(
        Evilution::Config,
        spec_files: [],
        target_files: ["lib/a.rb", "lib/b.rb"],
        spec_selector: selector
      )
      allow(Evilution::Config).to receive(:new).and_return(config)
      allow(Evilution::CLI::Printers::TestsList).to receive(:new).and_return(printer)

      parsed_files = Evilution::CLI::ParsedArgs.new(command: :tests_list, files: ["lib/a.rb", "lib/b.rb"])
      result = described_class.new(parsed_files, stdout: out, stderr: err).call

      expect(Evilution::CLI::Printers::TestsList).to have_received(:new).with(
        mode: :resolved,
        entries: [
          { source: "lib/a.rb", specs: ["spec/a_spec.rb"] },
          { source: "lib/b.rb", specs: [] }
        ]
      )
      expect(printer).to have_received(:render).with(out)
      expect(result.exit_code).to eq(0)
    end
  end

  describe "when target_files is empty" do
    it "falls through to Git::ChangedFiles" do
      selector = instance_double(Evilution::SpecSelector, call: ["spec/c_spec.rb"])
      config = instance_double(
        Evilution::Config,
        spec_files: [],
        target_files: [],
        spec_selector: selector
      )
      allow(Evilution::Config).to receive(:new).and_return(config)
      changed_files = instance_double(Evilution::Git::ChangedFiles, call: ["lib/c.rb"])
      allow(Evilution::Git::ChangedFiles).to receive(:new).and_return(changed_files)
      allow(Evilution::CLI::Printers::TestsList).to receive(:new).and_return(printer)

      parsed_no_files = Evilution::CLI::ParsedArgs.new(command: :tests_list)
      result = described_class.new(parsed_no_files, stdout: out, stderr: err).call

      expect(changed_files).to have_received(:call)
      expect(selector).to have_received(:call).with("lib/c.rb")
      expect(Evilution::CLI::Printers::TestsList).to have_received(:new).with(
        mode: :resolved,
        entries: [{ source: "lib/c.rb", specs: ["spec/c_spec.rb"] }]
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
