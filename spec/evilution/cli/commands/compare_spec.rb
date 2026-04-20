# frozen_string_literal: true

require "json"
require "stringio"
require "tempfile"
require "evilution/cli/commands/compare"
require "evilution/cli/parsed_args"

RSpec.describe Evilution::CLI::Commands::Compare do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:fixture_dir) { File.expand_path("../../../support/fixtures/compare", __dir__) }
  let(:mutant_path) { "#{fixture_dir}/mutant.json" }
  let(:evilution_path) { "#{fixture_dir}/evilution.json" }

  def parsed(files: [], options: {})
    Evilution::CLI::ParsedArgs.new(command: :compare, files: files, options: options)
  end

  def run_with(files: [], options: {})
    described_class.new(parsed(files: files, options: options), stdout: out, stderr: err).call
  end

  describe "path slot resolution" do
    it "maps two positional files to against/current in order" do
      result = run_with(files: [mutant_path, evilution_path])
      expect(result.exit_code).to eq(0)

      payload = JSON.parse(out.string)
      expect(payload["summary"]["shared_dead"]).to eq(3)
      expect(payload["summary"]["shared_alive"]).to eq(1)
    end

    it "uses --against and --current when both flags given" do
      result = run_with(
        files: [],
        options: { against: mutant_path, current: evilution_path }
      )
      expect(result.exit_code).to eq(0)

      payload = JSON.parse(out.string)
      expect(payload["summary"]["shared_dead"]).to eq(3)
      expect(payload["summary"]["shared_alive"]).to eq(1)
    end

    it "fills missing current slot from positional when only --against given" do
      result = run_with(
        files: [evilution_path],
        options: { against: mutant_path }
      )
      expect(result.exit_code).to eq(0)

      payload = JSON.parse(out.string)
      expect(payload["summary"]["shared_dead"]).to eq(3)
      expect(payload["summary"]["shared_alive"]).to eq(1)
    end

    it "fills missing against slot from positional when only --current given" do
      result = run_with(
        files: [mutant_path],
        options: { current: evilution_path }
      )
      expect(result.exit_code).to eq(0)

      payload = JSON.parse(out.string)
      expect(payload["summary"]["shared_dead"]).to eq(3)
      expect(payload["summary"]["shared_alive"]).to eq(1)
    end
  end

  describe "end-to-end with fixtures" do
    it "emits bucketed JSON with expected top-level keys" do
      result = run_with(files: [mutant_path, evilution_path])
      expect(result.exit_code).to eq(0)

      payload = JSON.parse(out.string)
      expect(payload.keys).to match_array(
        %w[schema summary alive_only_against alive_only_current shared_alive shared_dead]
      )
    end

    it "summary reflects fixture composition (3 shared_dead, 1 shared_alive)" do
      run_with(files: [mutant_path, evilution_path])

      payload = JSON.parse(out.string)
      summary = payload["summary"]
      expect(summary["shared_dead"]).to eq(3)
      expect(summary["shared_alive"]).to eq(1)
      expect(summary["alive_only_against"]).to eq(0)
      expect(summary["alive_only_current"]).to eq(0)
    end

    it "emits single-line JSON (no pretty-print)" do
      run_with(files: [mutant_path, evilution_path])
      # @stdout.puts appends exactly one trailing newline; rest must be single line.
      expect(out.string.count("\n")).to eq(1)
    end

    it "renders text output when --format text is given" do
      result = run_with(files: [mutant_path, evilution_path], options: { format: :text })
      expect(result.exit_code).to eq(0)
      expect(out.string).to include("Compare results")
      expect(out.string).to include("shared_dead")
    end
  end

  describe "error handling" do
    it "returns exit 2 with helpful message for missing files" do
      result = run_with(files: ["nope/missing.json", evilution_path])
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::Error)
      expect(result.error.message).to include("file not found", "nope/missing.json")
    end

    it "returns exit 2 with JSON parse error for malformed input" do
      Tempfile.create(["bad", ".json"]) do |f|
        f.write("not json{")
        f.flush

        result = run_with(files: [f.path, evilution_path])
        expect(result.exit_code).to eq(2)
        expect(result.error).to be_a(Evilution::Error)
        expect(result.error.message).to include("invalid JSON", f.path)
      end
    end

    it "returns exit 2 with InvalidInput message when detector cannot classify" do
      Tempfile.create(["ambig", ".json"]) do |f|
        f.write(JSON.generate({ "unknown" => true }))
        f.flush

        result = run_with(files: [f.path, evilution_path])
        expect(result.exit_code).to eq(2)
        expect(result.error).to be_a(Evilution::Error)
        expect(result.error.message).to include(f.path)
        expect(result.error.message).to include("cannot detect tool")
      end
    end

    it "returns exit 2 with ConfigError for unsupported --format" do
      result = run_with(
        files: [mutant_path, evilution_path],
        options: { format: :html }
      )
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
      expect(result.error.message).to include("compare supports --format")
    end
  end

  describe "wrong arg count" do
    it "returns exit 2 with ConfigError when no paths at all" do
      result = run_with(files: [])
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
      expect(result.error.message).to eq("exactly two file paths required for compare")
    end

    it "returns exit 2 when only one path given" do
      result = run_with(files: ["only.json"])
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
    end

    it "returns exit 2 when more than two positional paths given" do
      result = run_with(files: %w[a.json b.json c.json])
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
      expect(result.error.message).to eq("exactly two file paths required for compare")
    end

    it "returns exit 2 when flags plus extra positional overflow slots" do
      result = run_with(
        files: ["extra.json"],
        options: { against: "a.json", current: "b.json" }
      )
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
    end
  end

  it "is registered with the dispatcher under :compare" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:compare)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:compare)).to eq(described_class)
  end
end
