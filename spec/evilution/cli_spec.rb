# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "evilution/cli"

RSpec.describe Evilution::CLI do
  let(:summary) do
    instance_double(Evilution::Result::Summary, score: 1.0, success?: true)
  end

  let(:runner) { instance_double(Evilution::Runner, call: summary) }

  before do
    allow(Evilution::Runner).to receive(:new).and_return(runner)
    allow(summary).to receive(:success?).with(min_score: anything).and_return(true)
  end

  def capture_stdout
    io = StringIO.new
    original = $stdout
    $stdout = io
    yield
    io.string
  ensure
    $stdout = original
  end

  def capture_stderr
    io = StringIO.new
    original = $stderr
    $stderr = io
    yield
    io.string
  ensure
    $stderr = original
  end

  describe "version command" do
    it "outputs the gem version" do
      cli = described_class.new(["version"])
      output = capture_stdout { cli.call }
      expect(output).to include(Evilution::VERSION)
    end

    it "returns exit code 0" do
      cli = described_class.new(["version"])
      capture_stdout { expect(cli.call).to eq(0) }
    end
  end

  describe "init command" do
    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { example.run }
      end
    end

    it "creates .evilution.yml with default template" do
      cli = described_class.new(["init"])
      capture_stdout { cli.call }

      expect(File.exist?(".evilution.yml")).to be true
      content = File.read(".evilution.yml")
      expect(content).to include("# Evilution configuration")
    end

    it "returns exit code 0" do
      cli = described_class.new(["init"])
      capture_stdout { expect(cli.call).to eq(0) }
    end

    it "outputs a confirmation message" do
      cli = described_class.new(["init"])
      output = capture_stdout { cli.call }

      expect(output).to include("Created .evilution.yml")
    end

    it "returns exit code 1 if config file already exists" do
      File.write(".evilution.yml", "existing content")
      cli = described_class.new(["init"])
      capture_stderr { expect(cli.call).to eq(1) }
    end

    it "does not overwrite existing config file" do
      File.write(".evilution.yml", "existing content")
      cli = described_class.new(["init"])
      capture_stderr { cli.call }

      expect(File.read(".evilution.yml")).to eq("existing content")
    end
  end

  describe "run command" do
    describe "--format flag" do
      it "sets format to :json when --format json is given" do
        cli = described_class.new(["--format", "json"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(format: :json)
        )
      end

      it "sets format to :text when --format text is given" do
        cli = described_class.new(["--format", "text"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(format: :text)
        )
      end
    end

    describe "--jobs flag (deprecated)" do
      it "warns and does not crash" do
        expect { described_class.new(["--jobs", "4"]) }.to output(/no longer supported/).to_stderr
      end

      it "also handles the short form -j" do
        expect { described_class.new(["-j", "4"]) }.to output(/no longer supported/).to_stderr
      end

      it "also handles the attached short form -j4" do
        expect { described_class.new(["-j4"]) }.to output(/no longer supported/).to_stderr
      end

      it "also handles the attached long form --jobs=4" do
        expect { described_class.new(["--jobs=4"]) }.to output(/no longer supported/).to_stderr
      end

      it "does not appear in help output" do
        help_output = nil
        expect do
          described_class.new(["--help"])
        rescue SystemExit
          # --help causes SystemExit
        end.to output(satisfy { |out| help_output = out }).to_stdout
        expect(help_output).not_to include("--jobs")
      end
    end

    describe "--timeout flag" do
      it "sets timeout to the given integer" do
        cli = described_class.new(["--timeout", "30"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(timeout: 30)
        )
      end

      it "also accepts the short form -t" do
        cli = described_class.new(["-t", "5"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(timeout: 5)
        )
      end
    end

    describe "--quiet flag" do
      it "sets quiet to true" do
        cli = described_class.new(["--quiet"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(quiet: true)
        )
      end

      it "also accepts the short form -q" do
        cli = described_class.new(["-q"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(quiet: true)
        )
      end
    end

    describe "exit code" do
      it "returns 0 when the mutation score meets min_score" do
        allow(summary).to receive(:success?).with(min_score: 0.0).and_return(true)
        cli = described_class.new([])
        expect(cli.call).to eq(0)
      end

      it "returns 1 when the mutation score does not meet min_score" do
        allow(summary).to receive(:success?).with(min_score: 0.9).and_return(false)
        cli = described_class.new(["--min-score", "0.9"])
        expect(cli.call).to eq(1)
      end
    end

    describe "error handling" do
      it "returns exit code 2 for Evilution::Error" do
        allow(runner).to receive(:call).and_raise(Evilution::Error, "something failed")
        cli = described_class.new([])
        capture_stderr { expect(cli.call).to eq(2) }
      end

      it "prints the error message to stderr" do
        allow(runner).to receive(:call).and_raise(Evilution::Error, "something failed")
        cli = described_class.new([])
        output = capture_stderr { cli.call }

        expect(output).to include("Error: something failed")
      end
    end

    describe "positional file arguments" do
      it "passes remaining args as target_files" do
        cli = described_class.new(["lib/foo.rb", "lib/bar.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(target_files: ["lib/foo.rb", "lib/bar.rb"])
        )
      end

      it "accepts the explicit run subcommand before files" do
        cli = described_class.new(["run", "lib/foo.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(target_files: ["lib/foo.rb"])
        )
      end
    end

    describe "line-range targeting" do
      it "parses file:start-end into file path and line range" do
        cli = described_class.new(["lib/foo.rb:15-30"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(
            target_files: ["lib/foo.rb"],
            line_ranges: { "lib/foo.rb" => 15..30 }
          )
        )
      end

      it "parses file:line as a single-line range" do
        cli = described_class.new(["lib/foo.rb:15"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(
            target_files: ["lib/foo.rb"],
            line_ranges: { "lib/foo.rb" => 15..15 }
          )
        )
      end

      it "parses file:line- as open-ended range" do
        cli = described_class.new(["lib/foo.rb:15-"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(
            target_files: ["lib/foo.rb"],
            line_ranges: { "lib/foo.rb" => 15..Float::INFINITY }
          )
        )
      end

      it "passes plain files without line ranges" do
        cli = described_class.new(["lib/foo.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(
            target_files: ["lib/foo.rb"],
            line_ranges: {}
          )
        )
      end

      it "handles mixed arguments with and without ranges" do
        cli = described_class.new(["lib/foo.rb:10-20", "lib/bar.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(
            target_files: ["lib/foo.rb", "lib/bar.rb"],
            line_ranges: { "lib/foo.rb" => 10..20 }
          )
        )
      end
    end
  end
end
