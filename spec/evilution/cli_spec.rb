# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "mcp"
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

  describe "mcp command" do
    it "starts the MCP server" do
      transport = instance_double(MCP::Server::Transports::StdioTransport, open: nil)
      allow(MCP::Server::Transports::StdioTransport).to receive(:new).and_return(transport)

      cli = described_class.new(["mcp"])
      expect(cli.call).to eq(0)
      expect(transport).to have_received(:open)
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
          hooks: nil,
          config: have_attributes(format: :json)
        )
      end

      it "sets format to :text when --format text is given" do
        cli = described_class.new(["--format", "text"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(format: :text)
        )
      end
    end

    describe "--jobs flag" do
      it "sets jobs to the given integer" do
        cli = described_class.new(["--jobs", "4"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(jobs: 4)
        )
      end

      it "also accepts the short form -j" do
        cli = described_class.new(["-j", "2"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(jobs: 2)
        )
      end

      it "defaults to 1 when not specified" do
        cli = described_class.new([])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(jobs: 1)
        )
      end
    end

    describe "--timeout flag" do
      it "sets timeout to the given integer" do
        cli = described_class.new(["--timeout", "30"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(timeout: 30)
        )
      end

      it "also accepts the short form -t" do
        cli = described_class.new(["-t", "5"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(timeout: 5)
        )
      end
    end

    describe "--spec flag" do
      it "sets spec_files from comma-separated list" do
        cli = described_class.new(["--spec", "spec/foo_spec.rb,spec/bar_spec.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(spec_files: ["spec/foo_spec.rb", "spec/bar_spec.rb"])
        )
      end

      it "sets a single spec file" do
        cli = described_class.new(["--spec", "spec/foo_spec.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(spec_files: ["spec/foo_spec.rb"])
        )
      end
    end

    describe "--spec-dir flag" do
      around do |example|
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p("spec/requests")
            FileUtils.mkdir_p("spec/controllers")
            File.write("spec/requests/users_spec.rb", "")
            File.write("spec/requests/posts_spec.rb", "")
            File.write("spec/controllers/admin_spec.rb", "")
            example.run
          end
        end
      end

      it "expands directory to all spec files within it" do
        cli = described_class.new(["--spec-dir", "spec/requests"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(spec_files: contain_exactly(
            "spec/requests/users_spec.rb", "spec/requests/posts_spec.rb"
          ))
        )
      end

      it "combines with --spec flag" do
        cli = described_class.new(["--spec", "spec/controllers/admin_spec.rb", "--spec-dir", "spec/requests"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(spec_files: contain_exactly(
            "spec/controllers/admin_spec.rb",
            "spec/requests/users_spec.rb",
            "spec/requests/posts_spec.rb"
          ))
        )
      end

      it "errors when directory does not exist" do
        stderr = capture_stderr { described_class.new(["--spec-dir", "spec/nonexistent"]).call }
        expect(stderr).to include("not a directory")
      end
    end

    describe "--quiet flag" do
      it "sets quiet to true" do
        cli = described_class.new(["--quiet"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(quiet: true)
        )
      end

      it "also accepts the short form -q" do
        cli = described_class.new(["-q"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(quiet: true)
        )
      end
    end

    describe "--fail-fast flag" do
      it "sets fail_fast to 1 when given without a value" do
        cli = described_class.new(["--fail-fast"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(fail_fast: 1)
        )
      end

      it "sets fail_fast to the given integer" do
        cli = described_class.new(["--fail-fast", "5"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(fail_fast: 5)
        )
      end

      it "accepts --fail-fast=N form" do
        cli = described_class.new(["--fail-fast=3"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(fail_fast: 3)
        )
      end

      it "does not consume positional file arguments" do
        cli = described_class.new(["--fail-fast", "lib/foo.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
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

    describe "--suggest-tests flag" do
      it "sets suggest_tests to true" do
        cli = described_class.new(["--suggest-tests"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(suggest_tests: true)
        )
      end

      it "defaults to false when not specified" do
        cli = described_class.new([])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(suggest_tests: false)
        )
      end
    end

    describe "--show-disabled flag" do
      it "sets show_disabled to true" do
        cli = described_class.new(["--show-disabled"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(show_disabled: true)
        )
      end

      it "defaults to false when not specified" do
        cli = described_class.new([])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(show_disabled: false)
        )
      end
    end

    describe "--skip-heredoc-literals flag" do
      it "sets skip_heredoc_literals to true" do
        cli = described_class.new(["--skip-heredoc-literals"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(skip_heredoc_literals: true)
        )
      end

      it "defaults to false when not specified" do
        cli = described_class.new([])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(skip_heredoc_literals: false)
        )
      end
    end

    describe "--baseline-session flag" do
      it "sets baseline_session to the given path" do
        cli = described_class.new(["--baseline-session", "/tmp/session.json"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(baseline_session: "/tmp/session.json")
        )
      end

      it "defaults to nil when not specified" do
        cli = described_class.new([])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(baseline_session: nil)
        )
      end
    end

    describe "--no-progress flag" do
      it "sets progress to false" do
        cli = described_class.new(["--no-progress"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(progress: false)
        )
      end

      it "defaults to true when not specified" do
        cli = described_class.new([])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(progress: true)
        )
      end
    end

    describe "--target flag" do
      it "sets target on the config" do
        cli = described_class.new(["--target", "Foo#bar"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
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

    describe "hooks integration" do
      it "passes a Registry to Runner when hooks are configured" do
        hook_file = Tempfile.new(["hook", ".rb"])
        hook_file.write("proc { |_| nil }")
        hook_file.flush

        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            File.write(".evilution.yml", "hooks:\n  worker_process_start: #{hook_file.path}\n")
            allow(Evilution::Runner).to receive(:new).and_return(runner)

            cli = described_class.new([])
            cli.call

            expect(Evilution::Runner).to have_received(:new).with(
              hooks: an_instance_of(Evilution::Hooks::Registry),
              config: anything
            )
          end
        end
      ensure
        hook_file&.close
        hook_file&.unlink
      end

      it "returns exit code 2 when hook file is missing" do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            File.write(".evilution.yml", "hooks:\n  worker_process_start: /nonexistent/hook.rb\n")
            allow(Evilution::Runner).to receive(:new).and_return(runner)

            cli = described_class.new([])
            output = capture_stderr { expect(cli.call).to eq(2) }

            expect(output).to include("hook file not found")
          end
        end
      end

      it "returns exit code 2 when hooks is not a hash" do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            File.write(".evilution.yml", "hooks: not_a_hash\n")

            cli = described_class.new([])
            output = capture_stderr { expect(cli.call).to eq(2) }

            expect(output).to include("hooks must be a mapping")
          end
        end
      end
    end

    describe "positional file arguments" do
      it "passes remaining args as target_files" do
        cli = described_class.new(["lib/foo.rb", "lib/bar.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
          config: have_attributes(target_files: ["lib/foo.rb", "lib/bar.rb"])
        )
      end

      it "accepts the explicit run subcommand before files" do
        cli = described_class.new(["run", "lib/foo.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
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
          hooks: nil,
          config: have_attributes(target_files: ["lib/foo.rb", "lib/bar.rb"])
        )
      end

      it "supports line-range syntax in stdin lines" do
        stdin = StringIO.new("lib/foo.rb:15-30\n")
        cli = described_class.new(["--stdin"], stdin: stdin)
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          hooks: nil,
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
          hooks: nil,
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
          hooks: nil,
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
          hooks: nil,
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
          hooks: nil,
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
          hooks: nil,
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
          hooks: nil,
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
          hooks: nil,
          config: have_attributes(
            target_files: ["lib/foo.rb", "lib/bar.rb"],
            line_ranges: { "lib/foo.rb" => 10..20 }
          )
        )
      end
    end
  end

  describe "environment show command" do
    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { example.run }
      end
    end

    it "returns exit code 0" do
      cli = described_class.new(%w[environment show])
      capture_stdout { expect(cli.call).to eq(0) }
    end

    it "displays default configuration values" do
      cli = described_class.new(%w[environment show])
      output = capture_stdout { cli.call }

      expect(output).to include("timeout: 30")
      expect(output).to include("format: text")
      expect(output).to include("integration: rspec")
      expect(output).to include("jobs: 1")
      expect(output).to include("isolation: auto")
    end

    it "displays config file path when present" do
      File.write(".evilution.yml", "timeout: 60\njobs: 4\n")

      cli = described_class.new(%w[environment show])
      output = capture_stdout { cli.call }

      expect(output).to include("config_file: .evilution.yml")
      expect(output).to include("timeout: 60")
      expect(output).to include("jobs: 4")
    end

    it "shows no config file when none exists" do
      cli = described_class.new(%w[environment show])
      output = capture_stdout { cli.call }

      expect(output).to include("config_file: (none)")
    end

    it "reflects CLI overrides" do
      cli = described_class.new(["environment", "show", "--jobs", "8", "--timeout", "15"])
      output = capture_stdout { cli.call }

      expect(output).to include("jobs: 8")
      expect(output).to include("timeout: 15")
    end

    it "shows the Ruby and gem versions" do
      cli = described_class.new(%w[environment show])
      output = capture_stdout { cli.call }

      expect(output).to include("ruby: #{RUBY_VERSION}")
      expect(output).to include("evilution: #{Evilution::VERSION}")
    end

    it "handles invalid config file gracefully" do
      File.write(".evilution.yml", "{{invalid yaml")

      cli = described_class.new(%w[environment show])
      output = capture_stderr { expect(cli.call).to eq(2) }

      expect(output).to include("Error:")
    end

    it "shows error for unknown environment subcommand" do
      cli = described_class.new(%w[environment bogus])
      output = capture_stderr { cli.call }

      expect(output).to include("Unknown environment subcommand")
    end

    it "shows error for missing environment subcommand" do
      cli = described_class.new(%w[environment])
      output = capture_stderr { cli.call }

      expect(output).to include("Missing environment subcommand")
    end
  end

  describe "tests list command" do
    let(:resolver) { instance_double(Evilution::SpecResolver) }

    before do
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
    end

    it "returns exit code 0" do
      allow(resolver).to receive(:call).with("lib/example.rb").and_return("spec/example_spec.rb")

      cli = described_class.new(%w[tests list lib/example.rb])
      capture_stdout { expect(cli.call).to eq(0) }
    end

    it "lists spec files with source mapping" do
      allow(resolver).to receive(:call).with("lib/example.rb").and_return("spec/example_spec.rb")
      allow(resolver).to receive(:call).with("lib/user.rb").and_return("spec/user_spec.rb")

      cli = described_class.new(%w[tests list lib/example.rb lib/user.rb])
      output = capture_stdout { cli.call }

      expect(output).to include("spec/example_spec.rb")
      expect(output).to include("lib/example.rb")
      expect(output).to include("spec/user_spec.rb")
      expect(output).to include("lib/user.rb")
    end

    it "shows unresolved source files" do
      allow(resolver).to receive(:call).with("lib/example.rb").and_return("spec/example_spec.rb")
      allow(resolver).to receive(:call).with("lib/orphan.rb").and_return(nil)

      cli = described_class.new(%w[tests list lib/example.rb lib/orphan.rb])
      output = capture_stdout { cli.call }

      expect(output).to include("spec/example_spec.rb")
      expect(output).to include("lib/orphan.rb")
      expect(output).to include("no spec found")
    end

    it "shows summary with counts" do
      allow(resolver).to receive(:call).with("lib/example.rb").and_return("spec/example_spec.rb")
      allow(resolver).to receive(:call).with("lib/user.rb").and_return("spec/user_spec.rb")

      cli = described_class.new(%w[tests list lib/example.rb lib/user.rb])
      output = capture_stdout { cli.call }

      expect(output).to include("2 source files, 2 spec files")
    end

    it "deduplicates spec files" do
      allow(resolver).to receive(:call).with("lib/foo/bar.rb").and_return("spec/foo_spec.rb")
      allow(resolver).to receive(:call).with("lib/foo/baz.rb").and_return("spec/foo_spec.rb")

      cli = described_class.new(%w[tests list lib/foo/bar.rb lib/foo/baz.rb])
      output = capture_stdout { cli.call }

      expect(output).to include("2 source files, 1 spec file")
    end

    it "shows message when no files given and no changed files" do
      allow(Evilution::Git::ChangedFiles).to receive_message_chain(:new, :call)
        .and_raise(Evilution::Error, "no changed Ruby files found since merge base with master")

      cli = described_class.new(%w[tests list])
      output = capture_stdout { expect(cli.call).to eq(0) }

      expect(output).to include("No source files found")
    end

    it "uses --spec files when provided" do
      cli = described_class.new(%w[tests list --spec spec/custom_spec.rb])
      output = capture_stdout { cli.call }

      expect(output).to include("spec/custom_spec.rb")
    end

    it "shows error for unknown tests subcommand" do
      cli = described_class.new(%w[tests bogus])
      output = capture_stderr { cli.call }

      expect(output).to include("Unknown tests subcommand")
    end

    it "shows error for missing tests subcommand" do
      cli = described_class.new(%w[tests])
      output = capture_stderr { cli.call }

      expect(output).to include("Missing tests subcommand")
    end
  end

  describe "subjects command" do
    let(:subject1) do
      double("Subject",
             name: "Example#foo",
             file_path: "lib/example.rb",
             line_number: 10,
             source: "def foo\n  x + 1\nend",
             release_node!: nil)
    end

    let(:subject2) do
      double("Subject",
             name: "Example#bar",
             file_path: "lib/example.rb",
             line_number: 25,
             source: "def bar\n  y\nend",
             release_node!: nil)
    end

    before do
      allow(runner).to receive(:parse_and_filter_subjects).and_return([subject1, subject2])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).with(subject1, filter: anything).and_return([double, double, double])
      allow(registry).to receive(:mutations_for).with(subject2, filter: anything).and_return([double])
    end

    it "returns exit code 0" do
      cli = described_class.new(%w[subjects lib/example.rb])
      capture_stdout { expect(cli.call).to eq(0) }
    end

    it "lists subjects with file path and line number" do
      cli = described_class.new(%w[subjects lib/example.rb])
      output = capture_stdout { cli.call }

      expect(output).to include("Example#foo")
      expect(output).to include("lib/example.rb:10")
      expect(output).to include("Example#bar")
      expect(output).to include("lib/example.rb:25")
    end

    it "shows mutation count per subject" do
      cli = described_class.new(%w[subjects lib/example.rb])
      output = capture_stdout { cli.call }

      expect(output).to match(/Example#foo.*3 mutations/)
      expect(output).to match(/Example#bar.*1 mutation[^s]/)
    end

    it "shows total summary" do
      cli = described_class.new(%w[subjects lib/example.rb])
      output = capture_stdout { cli.call }

      expect(output).to include("2 subjects, 4 mutations")
    end

    it "shows message when no subjects found" do
      allow(runner).to receive(:parse_and_filter_subjects).and_return([])

      cli = described_class.new(%w[subjects lib/empty.rb])
      output = capture_stdout { cli.call }

      expect(output).to include("No subjects found")
    end

    it "passes target option to runner config" do
      allow(runner).to receive(:parse_and_filter_subjects).and_return([subject1])

      cli = described_class.new(%w[subjects --target Example#foo lib/example.rb])
      capture_stdout { cli.call }

      expect(Evilution::Runner).to have_received(:new).with(
        config: having_attributes(target: "Example#foo")
      )
    end

    it "passes line ranges to runner config" do
      allow(runner).to receive(:parse_and_filter_subjects).and_return([subject1])

      cli = described_class.new(%w[subjects lib/example.rb:10-20])
      capture_stdout { cli.call }

      expect(Evilution::Runner).to have_received(:new).with(
        config: having_attributes(line_ranges: { "lib/example.rb" => 10..20 })
      )
    end

    it "handles stdin file list" do
      allow(runner).to receive(:parse_and_filter_subjects).and_return([subject1])

      stdin = StringIO.new("lib/example.rb\n")
      cli = described_class.new(%w[subjects --stdin], stdin: stdin)
      capture_stdout { cli.call }

      expect(Evilution::Runner).to have_received(:new).with(
        config: having_attributes(target_files: %w[lib/example.rb])
      )
    end

    it "reports error for invalid config" do
      allow(runner).to receive(:parse_and_filter_subjects)
        .and_raise(Evilution::Error, "no files found matching 'nope'")

      cli = described_class.new(%w[subjects lib/example.rb])
      output = capture_stderr { expect(cli.call).to eq(2) }

      expect(output).to include("no files found matching")
    end
  end

  describe "session diff command" do
    let(:results_dir) { Dir.mktmpdir("evilution-sessions") }

    after { FileUtils.rm_rf(results_dir) }

    def write_session(filename, data)
      path = File.join(results_dir, filename)
      File.write(path, JSON.generate(data))
      path
    end

    def session_data(score:, total: 10, killed: 8, survived: 2, survivors: [])
      {
        "timestamp" => "2026-03-24T10:00:00+00:00",
        "summary" => {
          "total" => total,
          "killed" => killed,
          "survived" => survived,
          "timed_out" => 0,
          "errors" => 0,
          "neutral" => 0,
          "equivalent" => 0,
          "score" => score,
          "duration" => 5.0
        },
        "survived" => survivors
      }
    end

    def mutation(operator:, file:, line:, subject:)
      { "operator" => operator, "file" => file, "line" => line, "subject" => subject,
        "diff" => "- old\n+ new" }
    end

    let(:mutation_a) { mutation(operator: "arithmetic_replacement", file: "lib/foo.rb", line: 10, subject: "Foo#bar") }
    let(:mutation_b) { mutation(operator: "comparison_replacement", file: "lib/foo.rb", line: 20, subject: "Foo#baz") }

    it "returns exit code 0" do
      base = write_session("base.json", session_data(score: 0.8, survivors: [mutation_a]))
      head = write_session("head.json", session_data(score: 0.9, total: 10, killed: 9, survived: 1, survivors: [mutation_a]))

      cli = described_class.new(["session", "diff", base, head])
      capture_stdout { expect(cli.call).to eq(0) }
    end

    it "displays score delta" do
      base = write_session("base.json", session_data(score: 0.8, survivors: [mutation_a, mutation_b]))
      head = write_session("head.json", session_data(score: 0.9, total: 10, killed: 9, survived: 1, survivors: [mutation_a]))

      cli = described_class.new(["session", "diff", base, head])
      output = capture_stdout { cli.call }

      expect(output).to include("80.00%")
      expect(output).to include("90.00%")
      expect(output).to include("+10.00")
    end

    it "displays fixed mutations" do
      base = write_session("base.json", session_data(score: 0.8, survivors: [mutation_a, mutation_b]))
      head = write_session("head.json", session_data(score: 0.9, total: 10, killed: 9, survived: 1, survivors: [mutation_a]))

      cli = described_class.new(["session", "diff", base, head])
      output = capture_stdout { cli.call }

      expect(output).to include("Fixed")
      expect(output).to include("Foo#baz")
    end

    it "displays new survivors" do
      base = write_session("base.json", session_data(score: 0.9, total: 10, killed: 9, survived: 1, survivors: [mutation_a]))
      head = write_session("head.json", session_data(score: 0.8, survivors: [mutation_a, mutation_b]))

      cli = described_class.new(["session", "diff", base, head])
      output = capture_stdout { cli.call }

      expect(output).to include("New survivors")
      expect(output).to include("Foo#baz")
    end

    it "displays persistent survivors" do
      base = write_session("base.json", session_data(score: 0.8, survivors: [mutation_a]))
      head = write_session("head.json", session_data(score: 0.8, survivors: [mutation_a]))

      cli = described_class.new(["session", "diff", base, head])
      output = capture_stdout { cli.call }

      expect(output).to include("Persistent")
      expect(output).to include("Foo#bar")
    end

    it "shows no changes message when sessions are identical" do
      base = write_session("base.json", session_data(score: 1.0, total: 10, killed: 10, survived: 0, survivors: []))
      head = write_session("head.json", session_data(score: 1.0, total: 10, killed: 10, survived: 0, survivors: []))

      cli = described_class.new(["session", "diff", base, head])
      output = capture_stdout { cli.call }

      expect(output).to include("No mutation changes")
    end

    it "outputs JSON when --format json is given" do
      base = write_session("base.json", session_data(score: 0.8, survivors: [mutation_a]))
      head = write_session("head.json", session_data(score: 0.9, total: 10, killed: 9, survived: 1, survivors: [mutation_a]))

      cli = described_class.new(["session", "diff", "--format", "json", base, head])
      output = capture_stdout { cli.call }
      parsed = JSON.parse(output)

      expect(parsed["summary"]["score_delta"]).to eq(0.1)
      expect(parsed["fixed"]).to eq([])
      expect(parsed["new_survivors"]).to eq([])
    end

    it "returns exit code 2 when base file is missing" do
      head = write_session("head.json", session_data(score: 0.8, survivors: []))

      cli = described_class.new(["session", "diff", "/nonexistent.json", head])
      output = capture_stderr { expect(cli.call).to eq(2) }

      expect(output).to include("Error:")
    end

    it "returns exit code 2 when no file paths given" do
      cli = described_class.new(%w[session diff])
      output = capture_stderr { expect(cli.call).to eq(2) }

      expect(output).to include("two session file paths required")
    end

    it "returns exit code 2 when only one file path given" do
      base = write_session("base.json", session_data(score: 0.8, survivors: []))

      cli = described_class.new(["session", "diff", base])
      output = capture_stderr { expect(cli.call).to eq(2) }

      expect(output).to include("two session file paths required")
    end

    it "returns exit code 2 for unreadable session file" do
      head = write_session("head.json", session_data(score: 0.8, survivors: []))
      base_dir = File.join(results_dir, "not_a_file")
      Dir.mkdir(base_dir)

      cli = described_class.new(["session", "diff", base_dir, head])
      output = capture_stderr { expect(cli.call).to eq(2) }

      expect(output).to include("Error:")
    end

    it "updates available subcommands in error messages" do
      cli = described_class.new(%w[session bogus])
      output = capture_stderr { cli.call }

      expect(output).to include("diff")
    end
  end
end
