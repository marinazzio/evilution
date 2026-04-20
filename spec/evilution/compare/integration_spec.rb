# frozen_string_literal: true

require "json"
require "stringio"
require "evilution/cli"

# End-to-end integration for `evilution compare`. Exercises the full pipeline
# (Detector -> Normalizer -> Categorizer -> Printer) against realistic
# mutant.json and evilution.json fixtures with ZERO stubbing. The value of this
# spec is the wiring: bucket contents, summary counts, and format switching
# across every layer.
RSpec.describe "evilution compare (integration)" do
  fixture_dir = File.expand_path("../../support/fixtures/compare/e2e", __dir__)
  mutant_path = "#{fixture_dir}/mutant.json"
  evilution_path = "#{fixture_dir}/evilution.json"

  def run_cli(argv)
    captured = StringIO.new
    original = $stdout
    $stdout = captured
    exit_code = Evilution::CLI.new(argv).call
    { exit_code: exit_code, stdout: captured.string }
  ensure
    $stdout = original
  end

  describe "JSON format (default)" do
    let(:result) { run_cli(["compare", mutant_path, evilution_path]) }
    let(:payload) { JSON.parse(result[:stdout]) }

    it "exits 0" do
      expect(result[:exit_code]).to eq(0)
    end

    it "emits top-level keys in the documented order" do
      expect(payload.keys).to eq(
        %w[schema summary alive_only_against alive_only_current shared_alive shared_dead]
      )
    end

    it "summary matches the expected bucket distribution" do
      expect(payload["summary"]).to eq(
        "alive_only_against" => 1,
        "alive_only_current" => 1,
        "shared_alive" => 1,
        "shared_dead" => 1,
        "excluded_against" => 0,
        "excluded_current" => 1,
        "delta" => 0
      )
    end

    it "populates alive_only_against with one entry for lib/a.rb:10" do
      entries = payload["alive_only_against"]
      expect(entries.length).to eq(1)
      entry = entries.first
      expect(entry[0]).to eq("lib/a.rb")
      expect(entry[1]).to eq(10)
      # peer is absent (no evilution record for this fingerprint)
      expect(entry.last).to eq("absent")
    end

    it "populates alive_only_current with one entry for lib/a.rb:50" do
      entries = payload["alive_only_current"]
      expect(entries.length).to eq(1)
      entry = entries.first
      expect(entry[0]).to eq("lib/a.rb")
      expect(entry[1]).to eq(50)
      expect(entry.last).to eq("absent")
    end

    it "populates shared_alive with one paired entry at lib/a.rb:20" do
      entries = payload["shared_alive"]
      expect(entries.length).to eq(1)
      entry = entries.first
      expect(entry[0]).to eq("lib/a.rb")
      expect(entry[1]).to eq(20)
      # 4-tuple shape [file, line, operator, fp]
      expect(entry.length).to eq(4)
    end

    it "populates shared_dead with one paired entry at lib/a.rb:30" do
      entries = payload["shared_dead"]
      expect(entries.length).to eq(1)
      entry = entries.first
      expect(entry[0]).to eq("lib/a.rb")
      expect(entry[1]).to eq(30)
      expect(entry.length).to eq(4)
    end

    it "alive_only entries are 5-tuples per schema" do
      expect(payload["schema"]["alive_only"]).to eq(%w[file line operator fp other_status])
      expect(payload["alive_only_against"].first.length).to eq(5)
      expect(payload["alive_only_current"].first.length).to eq(5)
    end

    it "shared entries are 4-tuples per schema" do
      expect(payload["schema"]["shared"]).to eq(%w[file line operator fp])
    end
  end

  describe "text format (--format text)" do
    let(:result) { run_cli(["compare", "--format", "text", mutant_path, evilution_path]) }
    let(:output) { result[:stdout] }

    it "exits 0" do
      expect(result[:exit_code]).to eq(0)
    end

    it "prints the Compare results header" do
      expect(output).to include("Compare results")
    end

    it "summary line reflects expected counts" do
      expect(output).to include("alive_only_against=1")
      expect(output).to include("alive_only_current=1")
      expect(output).to include("shared_alive=1")
      expect(output).to include("shared_dead=1")
      expect(output).to include("excluded=0/1")
      expect(output).to include("delta=\u00B10")
    end

    it "renders bucket headers with their counts" do
      expect(output).to include("alive_only_against (1):")
      expect(output).to include("alive_only_current (1):")
      expect(output).to include("shared_alive (1):")
      expect(output).to include("shared_dead (1):")
    end

    it "shows the absent peer marker on both alive-only rows" do
      expect(output).to include("(current: absent)")
      expect(output).to include("(against: absent)")
    end

    it "shared rows omit peer markers" do
      # Extract the shared_alive section (between its header and the next header
      # or end of output) and confirm no peer marker snuck in.
      shared_alive_section = output.split("shared_alive (1):", 2).last.split("shared_dead", 2).first
      expect(shared_alive_section).not_to include("(current:")
      expect(shared_alive_section).not_to include("(against:")
    end
  end
end
