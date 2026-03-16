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

  describe "--version flag" do
    it "outputs the gem version and exits" do
      output = capture_stdout do
        expect { described_class.new(["--version"]) }.to raise_error(SystemExit) { |e|
          expect(e.status).to eq(0)
        }
      end
      expect(output).to include(Evilution::VERSION)
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

    describe "--jobs flag" do
      it "sets jobs to the given integer" do
        cli = described_class.new(["--jobs", "4"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(jobs: 4)
        )
      end

      it "also accepts the short form -j" do
        cli = described_class.new(["-j", "2"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(jobs: 2)
        )
      end

      it "defaults to 1 when not specified" do
        cli = described_class.new([])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(jobs: 1)
        )
      end
    end

    describe "--diff flag (deprecated)" do
      it "emits a deprecation warning to stderr" do
        expect { described_class.new(["--diff", "main"]) }.to output(/--diff is deprecated/).to_stderr
      end

      it "still sets diff_base on the config" do
        stderr = capture_stderr { described_class.new(["--diff", "main"]).call }
        expect(stderr).to include("--diff is deprecated")
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(diff_base: "main")
        )
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

    describe "--spec flag" do
      it "sets spec_files from comma-separated list" do
        cli = described_class.new(["--spec", "spec/foo_spec.rb,spec/bar_spec.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(spec_files: ["spec/foo_spec.rb", "spec/bar_spec.rb"])
        )
      end

      it "sets a single spec file" do
        cli = described_class.new(["--spec", "spec/foo_spec.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(spec_files: ["spec/foo_spec.rb"])
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

    describe "--fail-fast flag" do
      it "sets fail_fast to 1 when given without a value" do
        cli = described_class.new(["--fail-fast"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(fail_fast: 1)
        )
      end

      it "sets fail_fast to the given integer" do
        cli = described_class.new(["--fail-fast", "5"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(fail_fast: 5)
        )
      end

      it "accepts --fail-fast=N form" do
        cli = described_class.new(["--fail-fast=3"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(fail_fast: 3)
        )
      end

      it "does not consume positional file arguments" do
        cli = described_class.new(["--fail-fast", "lib/foo.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(fail_fast: 1, target_files: ["lib/foo.rb"])
        )
      end

      it "returns exit code 2 for invalid --fail-fast=abc" do
        cli = described_class.new(["--fail-fast=abc"])
        output = capture_stderr { expect(cli.call).to eq(2) }
        expect(output).to include("Error:")
      end

      it "returns exit code 2 for --fail-fast=0" do
        cli = described_class.new(["--fail-fast=0"])
        output = capture_stderr { expect(cli.call).to eq(2) }
        expect(output).to include("Error:")
      end

      it "returns exit code 2 for --fail-fast=-1" do
        cli = described_class.new(["--fail-fast=-1"])
        output = capture_stderr { expect(cli.call).to eq(2) }
        expect(output).to include("Error:")
      end

      it "returns exit code 2 for spaced --fail-fast -1" do
        cli = described_class.new(["--fail-fast", "-1"])
        output = capture_stderr { expect(cli.call).to eq(2) }
        expect(output).to include("Error:")
      end
    end

    describe "--no-coverage flag (deprecated)" do
      it "emits a deprecation warning to stderr" do
        expect { described_class.new(["--no-coverage"]) }.to output(/--no-coverage is deprecated.*no effect/).to_stderr
      end

      it "still sets coverage to false on the config" do
        stderr = capture_stderr { described_class.new(["--no-coverage"]).call }
        expect(stderr).to include("--no-coverage is deprecated")
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(coverage: false)
        )
      end
    end

    describe "--target flag" do
      it "sets target on the config" do
        cli = described_class.new(["--target", "Foo#bar"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(target: "Foo#bar")
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

      context "in JSON mode" do
        it "outputs structured JSON error to stdout for runtime errors" do
          allow(runner).to receive(:call).and_raise(Evilution::Error, "something failed")
          cli = described_class.new(["--format", "json"])
          output = capture_stdout { expect(cli.call).to eq(2) }
          parsed = JSON.parse(output)

          expect(parsed).to eq(
            "error" => { "type" => "runtime_error", "message" => "something failed" }
          )
        end

        it "outputs structured JSON error for config errors" do
          cli = described_class.new(["--format", "json", "--fail-fast=0"])
          output = capture_stdout { expect(cli.call).to eq(2) }
          parsed = JSON.parse(output)

          expect(parsed["error"]["type"]).to eq("config_error")
          expect(parsed["error"]["message"]).to include("positive integer")
        end

        it "outputs structured JSON error with file for parse errors" do
          error = Evilution::ParseError.new("file not found: lib/missing.rb", file: "lib/missing.rb")
          allow(runner).to receive(:call).and_raise(error)
          cli = described_class.new(["--format", "json"])
          output = capture_stdout { expect(cli.call).to eq(2) }
          parsed = JSON.parse(output)

          expect(parsed).to eq(
            "error" => {
              "type" => "parse_error",
              "message" => "file not found: lib/missing.rb",
              "file" => "lib/missing.rb"
            }
          )
        end

        it "uses JSON format when set via config file" do
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              File.write(".evilution.yml", "format: json\n")
              allow(Evilution::Runner).to receive(:new).and_return(runner)
              allow(runner).to receive(:call).and_raise(Evilution::Error, "something failed")
              cli = described_class.new([])
              output = capture_stdout { expect(cli.call).to eq(2) }
              parsed = JSON.parse(output)

              expect(parsed["error"]["type"]).to eq("runtime_error")
            end
          end
        end

        it "uses JSON format from config file even when Config.new fails" do
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              File.write(".evilution.yml", "format: json\nfail_fast: -1\n")
              cli = described_class.new([])
              output = capture_stdout { expect(cli.call).to eq(2) }
              parsed = JSON.parse(output)

              expect(parsed["error"]["type"]).to eq("config_error")
            end
          end
        end

        it "does not output to stderr" do
          allow(runner).to receive(:call).and_raise(Evilution::Error, "something failed")
          cli = described_class.new(["--format", "json"])
          stderr = capture_stderr { capture_stdout { cli.call } }

          expect(stderr).to be_empty
        end
      end

      context "in text mode" do
        it "prints plain text error to stderr without JSON" do
          allow(runner).to receive(:call).and_raise(Evilution::Error, "something failed")
          cli = described_class.new([])
          stderr = nil
          stdout = capture_stdout do
            stderr = capture_stderr { cli.call }
          end

          expect(stderr).to include("Error: something failed")
          expect(stderr).not_to include("{")
          expect(stdout).to be_empty
        end
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

    describe "--stdin flag" do
      it "reads file paths from stdin" do
        stdin = StringIO.new("lib/foo.rb\nlib/bar.rb\n")
        cli = described_class.new(["--stdin"], stdin: stdin)
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(target_files: ["lib/foo.rb", "lib/bar.rb"])
        )
      end

      it "supports line-range syntax in stdin lines" do
        stdin = StringIO.new("lib/foo.rb:15-30\n")
        cli = described_class.new(["--stdin"], stdin: stdin)
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(
            target_files: ["lib/foo.rb"],
            line_ranges: { "lib/foo.rb" => 15..30 }
          )
        )
      end

      it "skips blank lines" do
        stdin = StringIO.new("lib/foo.rb\n\n\nlib/bar.rb\n")
        cli = described_class.new(["--stdin"], stdin: stdin)
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(target_files: ["lib/foo.rb", "lib/bar.rb"])
        )
      end

      it "errors when combined with positional file args" do
        stdin = StringIO.new("lib/foo.rb\n")
        cli = described_class.new(["--stdin", "lib/bar.rb"], stdin: stdin)
        output = capture_stderr { expect(cli.call).to eq(2) }
        expect(output).to include("--stdin cannot be combined with positional file arguments")
      end

      it "outputs structured JSON error when combined with positional args in JSON mode" do
        stdin = StringIO.new("lib/foo.rb\n")
        cli = described_class.new(["--stdin", "--format", "json", "lib/bar.rb"], stdin: stdin)
        stderr = nil
        stdout = capture_stdout do
          stderr = capture_stderr { expect(cli.call).to eq(2) }
        end
        parsed = JSON.parse(stdout)

        expect(parsed["error"]["type"]).to eq("config_error")
        expect(parsed["error"]["message"]).to include("--stdin cannot be combined")
        expect(stderr).to be_empty
      end

      it "can be combined with other flags" do
        stdin = StringIO.new("lib/foo.rb\n")
        cli = described_class.new(["--stdin", "--format", "json", "-j", "4"], stdin: stdin)
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(
            target_files: ["lib/foo.rb"],
            format: :json,
            jobs: 4
          )
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
