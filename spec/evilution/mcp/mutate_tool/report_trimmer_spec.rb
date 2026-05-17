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

  # EV-187j / GH #1169: at summary verbosity, non-survived entries (timed_out,
  # errors, unresolved) must shed `diff` + `error_backtrace` payload. Survived
  # is the actionable list and keeps full detail.
  it "strips diff + error_backtrace from non-survived entries in summary mode" do
    json = JSON.generate({
                           "summary" => { "total" => 4 },
                           "survived" => [{ "operator" => "x", "file" => "f", "line" => 1, "diff" => "keep me" }],
                           "timed_out" => [{ "operator" => "x", "file" => "f", "line" => 2, "diff" => "drop",
                                             "error_backtrace" => ["bt"] }],
                           "errors" => [{ "operator" => "x", "file" => "f", "line" => 3, "diff" => "drop", "error_backtrace" => ["bt"],
                                          "error_message" => "boom" }],
                           "unresolved" => [{ "operator" => "x", "file" => "f", "line" => 4, "diff" => "drop",
                                              "error_backtrace" => ["bt"] }]
                         })
    out = JSON.parse(described_class.call(json, verbosity: "summary", survived_results: [], config: nil, enricher: noop_enricher))

    expect(out["survived"].first).to have_key("diff")
    %w[timed_out errors unresolved].each do |key|
      out[key].each do |entry|
        expect(entry).not_to have_key("diff"), "expected #{key} entry to drop diff"
        expect(entry).not_to have_key("error_backtrace"), "expected #{key} entry to drop error_backtrace"
      end
    end
    # error_message is preserved (1-line, diagnostic-critical, bounded).
    expect(out["errors"].first).to have_key("error_message")
  end

  it "leaves a non-Array summary-trim section untouched instead of iterating it" do
    # Guards `data[key].is_a?(Array)` in strip_heavy_fields: a String section is
    # truthy but cannot be iterated; real code returns early and leaves it intact.
    json = JSON.generate({ "summary" => { "total" => 1 }, "survived" => [],
                           "timed_out" => "not-an-array" })
    out = nil
    expect do
      out = JSON.parse(described_class.call(json, verbosity: "summary", survived_results: [],
                                                  config: nil, enricher: noop_enricher))
    end.not_to raise_error
    expect(out["timed_out"]).to eq("not-an-array")
  end

  it "keeps a 100-error summary payload comfortably under 50 KB" do
    long_bt = (1..40).map { |i| "lib/foo.rb:#{i}:in 'bar'" }
    huge_diff = "+ added line\n- removed line\n" * 50
    errors_arr = Array.new(100) do |i|
      {
        "operator" => "method_call_removal", "file" => "lib/foo.rb", "line" => i,
        "status" => "error", "duration" => 0.01, "diff" => huge_diff,
        "error_message" => "boom #{i}", "error_class" => "RuntimeError",
        "error_backtrace" => long_bt
      }
    end
    json = JSON.generate({ "summary" => { "total" => 100, "errors" => 100 }, "survived" => [], "errors" => errors_arr })
    out = described_class.call(json, verbosity: "summary", survived_results: [], config: nil, enricher: noop_enricher)

    expect(out.bytesize).to be < 50_000
  end

  it "whitelists summary + survived in minimal mode (and errors when present)" do
    out = JSON.parse(described_class.call(
                       json_input, verbosity: "minimal", survived_results: [], config: nil, enricher: noop_enricher
                     ))
    # json_input includes one errors entry, so it surfaces a trimmed sample.
    expect(out.keys).to contain_exactly("summary", "survived", "errors")
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
  TrimmerFrictionSummary = Struct.new(:errors, :unparseable, :unresolved, :total, :results, keyword_init: true) do
    def initialize(errors: 0, unparseable: 0, unresolved: 0, total: 0, results: [])
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

RSpec.describe Evilution::MCP::MutateTool::ReportTrimmer, "setup_warning embedding" do
  let(:bare_report) { JSON.generate({ "summary" => {}, "survived" => [] }) }
  let(:noop_enricher) { ->(_data, _survived, _config) {} }
  let(:config) { instance_double(Evilution::Config) }

  def errored_result(klass)
    double(error?: true, killed?: false, survived?: false, error_class: klass, status: :error)
  end

  let(:autoload_failure_summary) do
    results = Array.new(10) { errored_result("NameError") }
    instance_double(
      Evilution::Result::Summary,
      results: results,
      total: 10,
      errors: 10,
      unparseable: 0,
      unresolved: 0
    )
  end

  it "embeds setup_warning when nearly all mutations errored with the same class" do
    result = described_class.call(
      bare_report,
      verbosity: "summary",
      survived_results: [],
      config: config,
      enricher: noop_enricher,
      summary: autoload_failure_summary
    )
    data = JSON.parse(result)
    expect(data).to have_key("setup_warning")
    expect(data["setup_warning"]).to include("NameError")
    expect(data["setup_warning"]).to include("preload")
  end

  it "embeds setup_warning even at minimal verbosity (silent wrong scores are dangerous)" do
    result = described_class.call(
      JSON.generate({ "summary" => {}, "survived" => [], "killed" => [] }),
      verbosity: "minimal",
      survived_results: [],
      config: config,
      enricher: noop_enricher,
      summary: autoload_failure_summary
    )
    data = JSON.parse(result)
    expect(data["setup_warning"]).to include("preload")
  end

  it "omits setup_warning on a clean summary" do
    clean_summary = instance_double(
      Evilution::Result::Summary,
      results: [], total: 0, errors: 0, unparseable: 0, unresolved: 0
    )
    result = described_class.call(
      bare_report,
      verbosity: "summary",
      survived_results: [],
      config: config,
      enricher: noop_enricher,
      summary: clean_summary
    )
    data = JSON.parse(result)
    expect(data).not_to have_key("setup_warning")
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

# EV-t7kh / GH #1170: at minimal verbosity, surface a trimmed sample of
# errored mutations so agents are not stuck in a diagnose-vs-token-cap deadlock.
RSpec.describe Evilution::MCP::MutateTool::ReportTrimmer, "minimal verbosity errors sample" do
  let(:noop_enricher) { ->(_data, _survived, _config) {} }
  let(:long_backtrace) { (1..20).map { |i| "lib/foo.rb:#{i}:in 'bar'" } }

  it "includes a trimmed errors sample when errors are present" do
    json = JSON.generate({
                           "summary" => { "total" => 5, "errors" => 5 },
                           "survived" => [],
                           "errors" => Array.new(5) do |i|
                             {
                               "operator" => "method_call_removal", "file" => "lib/foo.rb", "line" => i,
                               "status" => "error", "duration" => 0.01, "diff" => "huge diff",
                               "error_message" => "boom #{i}", "error_class" => "RuntimeError",
                               "error_backtrace" => long_backtrace
                             }
                           end
                         })
    out = JSON.parse(described_class.call(json, verbosity: "minimal", survived_results: [], config: nil, enricher: noop_enricher))

    expect(out["errors"].length).to eq(3)
    out["errors"].each do |entry|
      expect(entry).to have_key("error_message")
      expect(entry["error_backtrace"].length).to eq(5)
      expect(entry).not_to have_key("diff")
    end
  end

  it "does not add an errors field when no errors are present" do
    json = JSON.generate({ "summary" => { "total" => 1, "errors" => 0 }, "survived" => [], "errors" => [] })
    out = JSON.parse(described_class.call(json, verbosity: "minimal", survived_results: [], config: nil, enricher: noop_enricher))

    expect(out).not_to have_key("errors")
  end

  it "ignores a non-Array errors payload instead of mis-sampling it" do
    # Guards `entries.is_a?(Array)` in error_sample: a Hash is truthy and answers
    # #empty?, but must not be treated as a sample-able list. Real code drops it.
    json = JSON.generate({ "summary" => { "total" => 1 }, "survived" => [],
                           "errors" => { "operator" => "x" } })
    out = nil
    expect do
      out = JSON.parse(described_class.call(json, verbosity: "minimal", survived_results: [],
                                                  config: nil, enricher: noop_enricher))
    end.not_to raise_error
    expect(out).not_to have_key("errors")
  end

  it "skips a non-Array error_backtrace when trimming an error entry" do
    # Guards `backtrace.is_a?(Array)` in trim_error_entry: a String backtrace
    # must not be passed to #first, and must not appear in the trimmed entry.
    json = JSON.generate({
                           "summary" => { "total" => 1, "errors" => 1 },
                           "survived" => [],
                           "errors" => [{
                             "operator" => "method_call_removal", "file" => "lib/foo.rb", "line" => 1,
                             "error_message" => "boom", "error_class" => "RuntimeError",
                             "error_backtrace" => "not-an-array"
                           }]
                         })
    out = nil
    expect do
      out = JSON.parse(described_class.call(json, verbosity: "minimal", survived_results: [],
                                                  config: nil, enricher: noop_enricher))
    end.not_to raise_error
    expect(out["errors"].first).not_to have_key("error_backtrace")
    expect(out["errors"].first["error_message"]).to eq("boom")
  end
end
