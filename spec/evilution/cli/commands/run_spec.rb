# frozen_string_literal: true

require "stringio"
require "json"
require "tmpdir"
require "evilution/cli/commands/run"
require "evilution/cli/parsed_args"

RSpec.describe Evilution::CLI::Commands::Run do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:summary) { instance_double(Evilution::Result::Summary) }
  let(:runner) { instance_double(Evilution::Runner, call: summary) }
  let(:parsed) { Evilution::CLI::ParsedArgs.new(command: :run, files: ["lib/a.rb"]) }

  before do
    allow(Evilution::Runner).to receive(:new).and_return(runner)
    allow(summary).to receive(:success?).with(min_score: anything).and_return(true)
  end

  describe "happy path" do
    it "returns Result with exit_code 0 when summary meets min_score" do
      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(0)
      expect(result.error).to be_nil
      expect(result.error_rendered).to be(false)
    end

    it "returns Result with exit_code 1 when summary does not meet min_score" do
      allow(summary).to receive(:success?).with(min_score: anything).and_return(false)

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(1)
      expect(result.error).to be_nil
    end
  end

  describe "stdin error" do
    it "raises ConfigError → Result exit 2 with error set, not rendered" do
      parsed_with_err = Evilution::CLI::ParsedArgs.new(
        command: :run,
        stdin_error: "--stdin cannot be combined with positional file arguments"
      )

      result = described_class.new(parsed_with_err, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
      expect(result.error_rendered).to be(false)
      expect(out.string).to be_empty
    end
  end

  describe "Evilution::Error from runner (text mode)" do
    it "returns Result exit 2 with error set and not rendered" do
      allow(runner).to receive(:call).and_raise(Evilution::Error, "boom")

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::Error)
      expect(result.error.message).to eq("boom")
      expect(result.error_rendered).to be(false)
      expect(out.string).to be_empty
      # stderr carries the Surface 2 feedback footer (full assertions in the
      # dedicated "feedback footer on error path" describe block below).
    end
  end

  describe "Evilution::Error in JSON mode via CLI flag" do
    let(:parsed) do
      Evilution::CLI::ParsedArgs.new(command: :run, files: ["lib/a.rb"], options: { format: :json })
    end

    it "emits JSON payload to stdout and marks error_rendered" do
      allow(runner).to receive(:call).and_raise(Evilution::Error, "boom")

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(2)
      expect(result.error_rendered).to be(true)
      payload = JSON.parse(out.string)
      expect(payload).to eq("error" => { "type" => "runtime_error", "message" => "boom" })
    end

    it "uses config_error type for ConfigError" do
      allow(runner).to receive(:call).and_raise(Evilution::ConfigError, "bad config")

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(2)
      payload = JSON.parse(out.string)
      expect(payload["error"]["type"]).to eq("config_error")
      expect(payload["error"]["message"]).to eq("bad config")
    end

    it "uses parse_error type and includes file for ParseError with file" do
      error = Evilution::ParseError.new("missing", file: "lib/missing.rb")
      allow(runner).to receive(:call).and_raise(error)

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(2)
      payload = JSON.parse(out.string)
      expect(payload).to eq(
        "error" => { "type" => "parse_error", "message" => "missing", "file" => "lib/missing.rb" }
      )
    end

    it "omits file field when error.file is nil" do
      allow(runner).to receive(:call).and_raise(Evilution::ParseError.new("oops"))

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(2)
      payload = JSON.parse(out.string)
      expect(payload["error"]).not_to have_key("file")
    end
  end

  describe "#error_payload file field" do
    it "omits the file field for an error that does not respond to :file" do
      command = described_class.new(parsed, stdout: out, stderr: err)
      error = Class.new(StandardError) { def message = "no file accessor" }.new

      payload = command.send(:error_payload, error)

      expect(payload[:error]).not_to have_key(:file)
      expect(payload[:error][:message]).to eq("no file accessor")
    end
  end

  describe "JSON format via file_options when Config.new fails" do
    it "still emits JSON payload to stdout" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write(".evilution.yml", "format: json\nfail_fast: -1\n")

          result = described_class.new(parsed, stdout: out, stderr: err).call

          expect(result.exit_code).to eq(2)
          expect(result.error_rendered).to be(true)
          payload = JSON.parse(out.string)
          expect(payload["error"]["type"]).to eq("config_error")
        end
      end
    end
  end

  describe "hooks wiring" do
    let(:config) { instance_double(Evilution::Config) }
    let(:registry) { instance_double(Evilution::Hooks::Registry) }

    before do
      allow(Evilution::Config).to receive(:new).and_return(config)
      allow(config).to receive(:min_score).and_return(0.0)
    end

    it "builds a hook registry and passes it to the Runner when config.hooks is non-empty" do
      allow(config).to receive(:hooks).and_return(["lib/hook.rb"])
      allow(Evilution::Hooks::Registry).to receive(:new).and_return(registry)
      allow(Evilution::Hooks::Loader).to receive(:call)

      described_class.new(parsed, stdout: out, stderr: err).call

      expect(Evilution::Hooks::Loader).to have_received(:call).with(registry, ["lib/hook.rb"])
      expect(Evilution::Runner).to have_received(:new).with(config: config, hooks: registry)
    end

    it "passes hooks: nil to the Runner when config.hooks is empty" do
      allow(config).to receive(:hooks).and_return([])

      described_class.new(parsed, stdout: out, stderr: err).call

      expect(Evilution::Runner).to have_received(:new).with(config: config, hooks: nil)
    end

    it "does not build a registry or invoke the Loader when config.hooks is empty" do
      allow(config).to receive(:hooks).and_return([])
      allow(Evilution::Hooks::Registry).to receive(:new)
      allow(Evilution::Hooks::Loader).to receive(:call)

      described_class.new(parsed, stdout: out, stderr: err).call

      expect(Evilution::Hooks::Registry).not_to have_received(:new)
      expect(Evilution::Hooks::Loader).not_to have_received(:call)
    end
  end

  describe "json mode selection from config" do
    it "uses config.json? to route an error to JSON output when no CLI format flag is set" do
      config = instance_double(Evilution::Config, hooks: [], min_score: 0.0, quiet: false, json?: true)
      allow(Evilution::Config).to receive(:new).and_return(config)
      allow(runner).to receive(:call).and_raise(Evilution::Error, "boom")

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.error_rendered).to be(true)
      payload = JSON.parse(out.string)
      expect(payload["error"]["message"]).to eq("boom")
    end
  end

  it "is registered with the dispatcher under :run" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:run)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:run)).to eq(described_class)
  end
end

RSpec.describe Evilution::CLI::Commands::Run, "feedback footer on error path (Surface 2)" do
  require "evilution/feedback"
  require "evilution/feedback/messages"

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def parsed(options)
    Evilution::CLI::ParsedArgs.new(command: :run, files: [], options: options)
  end

  before do
    # Force an Evilution::ConfigError early in #call so #handle_error runs.
    allow(Evilution::Config).to receive(:new).and_raise(Evilution::ConfigError, "boom")
    allow(Evilution::Config).to receive(:file_options).and_return(nil)
  end

  it "emits the feedback footer on stderr in text mode" do
    described_class.new(parsed(format: :text), stdout: stdout, stderr: stderr).call
    expect(stderr.string).to include(Evilution::Feedback::Messages.cli_footer)
  end

  it "does NOT emit the feedback footer on stderr in json mode" do
    described_class.new(parsed(format: :json), stdout: stdout, stderr: stderr).call
    expect(stderr.string).not_to include(Evilution::Feedback::DISCUSSION_URL)
  end

  it "does NOT emit the feedback footer on stderr when quiet=true" do
    described_class.new(parsed(format: :text, quiet: true), stdout: stdout, stderr: stderr).call
    expect(stderr.string).not_to include(Evilution::Feedback::DISCUSSION_URL)
  end

  describe "quiet decided by a successfully built config" do
    let(:runner) { instance_double(Evilution::Runner) }

    before do
      allow(Evilution::Config).to receive(:new).and_call_original
      allow(Evilution::Runner).to receive(:new).and_return(runner)
      allow(runner).to receive(:call).and_raise(Evilution::Error, "boom")
    end

    it "suppresses the footer when config.quiet is true" do
      config = instance_double(Evilution::Config, quiet: true, json?: false, hooks: [])
      allow(Evilution::Config).to receive(:new).and_return(config)

      described_class.new(parsed(format: :text), stdout: stdout, stderr: stderr).call

      expect(stderr.string).not_to include(Evilution::Feedback::DISCUSSION_URL)
    end

    it "emits the footer when config.quiet is false" do
      config = instance_double(Evilution::Config, quiet: false, json?: false, hooks: [])
      allow(Evilution::Config).to receive(:new).and_return(config)

      described_class.new(parsed(format: :text), stdout: stdout, stderr: stderr).call

      expect(stderr.string).to include(Evilution::Feedback::Messages.cli_footer)
    end
  end

  describe "quiet decided by file_options when config build fails" do
    around do |example|
      Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
    end

    before { allow(Evilution::Config).to receive(:file_options).and_call_original }

    it "suppresses the footer when file_options requests quiet" do
      File.write(".evilution.yml", "quiet: true\nfail_fast: -1\n")

      described_class.new(parsed(format: :text), stdout: stdout, stderr: stderr).call

      expect(stderr.string).not_to include(Evilution::Feedback::DISCUSSION_URL)
    end

    it "emits the footer when file_options has no quiet key" do
      File.write(".evilution.yml", "format: text\nfail_fast: -1\n")

      described_class.new(parsed(format: :text), stdout: stdout, stderr: stderr).call

      expect(stderr.string).to include(Evilution::Feedback::Messages.cli_footer)
    end
  end
end
