# frozen_string_literal: true

require "evilution/mcp/mutate_tool"

RSpec.describe Evilution::MCP::MutateTool::ReportTrimmer do
  let(:noop_enricher) { ->(*_) {} }
  let(:json_input) do
    {
      "version" => "1.2.3",
      "timestamp" => "2026-04-18T00:00:00Z",
      "summary" => { "total" => 6 },
      "survived" => [{ "id" => 1 }],
      "coverage_gaps" => [{ "file" => "a.rb" }],
      "killed" => [{ "id" => 2, "diff" => "diff" }],
      "neutral" => [{ "id" => 3, "diff" => "diff" }],
      "equivalent" => [{ "id" => 4, "diff" => "diff" }],
      "timed_out" => [{ "id" => 5 }],
      "errors" => [{ "id" => 6 }],
      "unresolved" => [{ "id" => 7, "diff" => "diff" }],
      "unparseable" => [{ "id" => 9, "diff" => "diff" }],
      "disabled" => [{ "id" => 8 }]
    }.to_json
  end

  it "strips diffs from killed/neutral/equivalent/unresolved/unparseable in full mode" do
    out = JSON.parse(described_class.call(
                       json_input, verbosity: "full", survived_results: [], config: nil, enricher: noop_enricher
                     ))
    expect(out["killed"].first).not_to have_key("diff")
    expect(out["neutral"].first).not_to have_key("diff")
    expect(out["equivalent"].first).not_to have_key("diff")
    expect(out["unresolved"].first).not_to have_key("diff")
    expect(out["unparseable"].first).not_to have_key("diff")
  end

  it "removes killed/neutral/equivalent/unparseable in summary mode" do
    out = JSON.parse(described_class.call(
                       json_input, verbosity: "summary", survived_results: [], config: nil, enricher: noop_enricher
                     ))
    %w[killed neutral equivalent unparseable].each { |key| expect(out).not_to have_key(key) }
    expect(out).to have_key("timed_out")
  end

  it "whitelists only summary + survived in minimal mode" do
    out = JSON.parse(described_class.call(
                       json_input, verbosity: "minimal", survived_results: [], config: nil, enricher: noop_enricher
                     ))
    expect(out.keys).to contain_exactly("summary", "survived")
  end

  it "handles missing diff-bearing sections in full mode without raising" do
    sparse = { "summary" => { "total" => 0 }, "survived" => [] }.to_json
    expect do
      described_class.call(sparse, verbosity: "full", survived_results: [], config: nil, enricher: noop_enricher)
    end.not_to raise_error
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

require "evilution/feedback"
require "evilution/feedback/messages"

unless defined?(TrimmerFrictionSummary)
  TrimmerFrictionSummary = Struct.new(:errors, :unparseable, :unresolved, keyword_init: true) do
    def initialize(errors: 0, unparseable: 0, unresolved: 0)
      super
    end
  end
end

RSpec.describe Evilution::MCP::MutateTool::ReportTrimmer, "feedback embedding" do
  let(:bare_report) { JSON.generate({ "summary" => {}, "survived" => [] }) }
  let(:noop_enricher) { ->(_data, _survived, _config) {} }
  let(:config) { instance_double(Evilution::Config) }

  it "embeds feedback_url + feedback_hint when summary has friction" do
    result = described_class.call(
      bare_report,
      verbosity: "summary",
      survived_results: [],
      config: config,
      enricher: noop_enricher,
      summary: TrimmerFrictionSummary.new(errors: 1)
    )
    data = JSON.parse(result)
    expect(data["feedback_url"]).to eq(Evilution::Feedback::DISCUSSION_URL)
    expect(data["feedback_hint"]).to eq(Evilution::Feedback::Messages.mcp_hint)
  end

  it "omits feedback fields on a clean summary" do
    result = described_class.call(
      bare_report,
      verbosity: "summary",
      survived_results: [],
      config: config,
      enricher: noop_enricher,
      summary: TrimmerFrictionSummary.new
    )
    data = JSON.parse(result)
    expect(data).not_to have_key("feedback_url")
    expect(data).not_to have_key("feedback_hint")
  end
end

RSpec.describe Evilution::MCP::MutateTool::ReportTrimmer, "minimal verbosity preserves contract" do
  let(:bare_report) { JSON.generate({ "summary" => {}, "survived" => [], "killed" => [] }) }
  let(:noop_enricher) { ->(_data, _survived, _config) {} }
  let(:config) { instance_double(Evilution::Config) }

  it "does NOT embed feedback fields when verbosity=minimal even on friction" do
    result = described_class.call(
      bare_report,
      verbosity: "minimal",
      survived_results: [],
      config: config,
      enricher: noop_enricher,
      summary: TrimmerFrictionSummary.new(errors: 5)
    )
    data = JSON.parse(result)
    expect(data).not_to have_key("feedback_url")
    expect(data).not_to have_key("feedback_hint")
    expect(data.keys).to contain_exactly("summary", "survived")
  end
end
