# frozen_string_literal: true

require "evilution/mcp/mutate_tool"

RSpec.describe Evilution::MCP::MutateTool::ReportTrimmer do
  let(:noop_enricher) { ->(*_) {} }
  let(:json_input) do
    {
      "survived" => [{ "id" => 1 }],
      "killed" => [{ "id" => 2, "diff" => "diff" }],
      "neutral" => [{ "id" => 3, "diff" => "diff" }],
      "equivalent" => [{ "id" => 4, "diff" => "diff" }],
      "timed_out" => [{ "id" => 5 }],
      "errors" => [{ "id" => 6 }]
    }.to_json
  end

  it "strips diffs from killed/neutral/equivalent in full mode" do
    out = JSON.parse(described_class.call(
                       json_input, verbosity: "full", survived_results: [], config: nil, enricher: noop_enricher
                     ))
    expect(out["killed"].first).not_to have_key("diff")
    expect(out["neutral"].first).not_to have_key("diff")
    expect(out["equivalent"].first).not_to have_key("diff")
  end

  it "removes killed/neutral/equivalent in summary mode" do
    out = JSON.parse(described_class.call(
                       json_input, verbosity: "summary", survived_results: [], config: nil, enricher: noop_enricher
                     ))
    %w[killed neutral equivalent].each { |key| expect(out).not_to have_key(key) }
    expect(out).to have_key("timed_out")
  end

  it "also removes timed_out and errors in minimal mode" do
    out = JSON.parse(described_class.call(
                       json_input, verbosity: "minimal", survived_results: [], config: nil, enricher: noop_enricher
                     ))
    %w[killed neutral equivalent timed_out errors].each { |key| expect(out).not_to have_key(key) }
    expect(out).to have_key("survived")
  end

  it "delegates to the enricher with parsed data, survived_results, and config" do
    captured = nil
    survived = [:a]
    cfg = Object.new
    enricher = ->(data, results, config) { captured = [data, results, config] }

    described_class.call(json_input, verbosity: "full", survived_results: survived, config: cfg, enricher: enricher)
    expect(captured[0]["survived"]).to eq([{ "id" => 1 }])
    expect(captured[1]).to be(survived)
    expect(captured[2]).to be(cfg)
  end
end
