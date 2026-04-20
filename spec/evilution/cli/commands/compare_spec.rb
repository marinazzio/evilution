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
      expect(payload["against"]["path"]).to eq(mutant_path)
      expect(payload["current"]["path"]).to eq(evilution_path)
    end

    it "uses --against and --current when both flags given" do
      result = run_with(
        files: [],
        options: { against: mutant_path, current: evilution_path }
      )
      expect(result.exit_code).to eq(0)

      payload = JSON.parse(out.string)
      expect(payload["against"]["path"]).to eq(mutant_path)
      expect(payload["current"]["path"]).to eq(evilution_path)
    end

    it "fills missing current slot from positional when only --against given" do
      result = run_with(
        files: [evilution_path],
        options: { against: mutant_path }
      )
      expect(result.exit_code).to eq(0)

      payload = JSON.parse(out.string)
      expect(payload["against"]["path"]).to eq(mutant_path)
      expect(payload["current"]["path"]).to eq(evilution_path)
    end

    it "fills missing against slot from positional when only --current given" do
      result = run_with(
        files: [mutant_path],
        options: { current: evilution_path }
      )
      expect(result.exit_code).to eq(0)

      payload = JSON.parse(out.string)
      expect(payload["against"]["path"]).to eq(mutant_path)
      expect(payload["current"]["path"]).to eq(evilution_path)
    end
  end

  describe "end-to-end with fixtures" do
    it "emits JSON with normalized records from both tools" do
      result = run_with(files: [mutant_path, evilution_path])
      expect(result.exit_code).to eq(0)

      payload = JSON.parse(out.string)
      expect(payload.keys).to match_array(%w[against current])

      expect(payload["against"]["tool"]).to eq("mutant")
      expect(payload["against"]["path"]).to eq(mutant_path)
      expect(payload["against"]["records"].size).to eq(4)

      expect(payload["current"]["tool"]).to eq("evilution")
      expect(payload["current"]["path"]).to eq(evilution_path)
      expect(payload["current"]["records"].size).to eq(4)
    end

    it "produces matching fingerprints for equivalent mutations" do
      run_with(files: [mutant_path, evilution_path])

      payload = JSON.parse(out.string)
      mutant_fps = payload["against"]["records"].map { |r| r["fingerprint"] }.sort
      evo_fps = payload["current"]["records"].map { |r| r["fingerprint"] }.sort
      expect(mutant_fps).to eq(evo_fps)
    end

    it "serializes symbol status and source fields as strings" do
      run_with(files: [mutant_path, evilution_path])

      payload = JSON.parse(out.string)
      mutant_records = payload["against"]["records"]
      evo_records = payload["current"]["records"]

      expect(mutant_records.map { |r| r["source"] }.uniq).to eq(["mutant"])
      expect(evo_records.map { |r| r["source"] }.uniq).to eq(["evilution"])

      evo_statuses = evo_records.map { |r| r["status"] }
      expect(evo_statuses).to all(be_a(String))
      expect(evo_statuses.sort).to eq(%w[killed killed survived timeout])
    end

    it "emits single-line JSON (no pretty-print)" do
      run_with(files: [mutant_path, evilution_path])
      # @stdout.puts appends exactly one trailing newline; rest must be single line.
      expect(out.string.count("\n")).to eq(1)
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
