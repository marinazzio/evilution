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
end
