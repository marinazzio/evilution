# frozen_string_literal: true

require_relative "../../../scripts/lib/benchmark_perf/report"

RSpec.describe BenchmarkPerf::Report do
  def sample(wall:, statuses:, operators: { "cmp" => { count: 2, duration: 1.0 } })
    run = BenchmarkPerf::RunResult.new(wall: wall, duration: wall, killtime: 1.0,
                                       statuses: statuses, operators: operators)
    BenchmarkPerf::VersionSample.new(runs: [run])
  end

  def failed_sample
    BenchmarkPerf::VersionSample.new(runs: [BenchmarkPerf::RunResult.failed("exit 1: no JSON", wall: 1.0)])
  end

  let(:base) { sample(wall: 10.0, statuses: { "lib/a.rb:1:cmp" => "killed", "lib/a.rb:2:cmp" => "killed" }) }
  let(:other) { sample(wall: 20.0, statuses: { "lib/a.rb:1:cmp" => "survived", "lib/a.rb:2:cmp" => "killed" }) }
  let(:samples) do
    {
      "fixture" => { "v1.5.0" => base, "HEAD" => other },
      "redmine" => { "v1.5.0" => base, "HEAD" => failed_sample }
    }
  end
  let(:markdown) do
    described_class.new(versions: %w[v1.5.0 HEAD],
                        version_labels: { "v1.5.0" => "abc1234", "HEAD" => "def5678" },
                        samples: samples, repeats: 3).to_markdown
  end

  it "names each version with its label and marks the baseline" do
    expect(markdown).to include("v1.5.0", "abc1234", "def5678", "baseline")
  end

  it "lists lost kills under their target" do
    fixture_section = markdown.split("## redmine").first

    expect(fixture_section).to include("Lost kills: 1", "lib/a.rb:1:cmp")
  end

  it "shows a failed version and still renders the other targets" do
    expect(markdown).to include("FAILED: exit 1: no JSON", "n/a (failed run)", "## fixture", "## redmine")
  end

  it "explains that operator rows are killtime shares" do
    expect(markdown).to include(
      "Operator rows are shares of killtime (sum of per-mutation durations); " \
      "with --jobs > 1 they do not add up to Δwall."
    )
  end

  it "shows a dash for missing per-phase timings" do
    expect(markdown).to match(/\| —\s*\|/)
  end

  it "includes totals across targets" do
    expect(markdown).to include("## Totals")
  end

  describe "totals" do
    let(:totals) { markdown.split("## Totals").last }

    it "sums only targets where every version succeeded and names the excluded ones" do
      expect(totals).to include("| v1.5.0 | 10.0 | 2 |", "| HEAD | 20.0 | 2 | +10.0 |")
      expect(totals).to include("Excluded from totals: redmine (HEAD failed)")
    end
  end

  it "shows killtime per mutant and the relative wall change" do
    expect(markdown).to include("killtime/mutant s", "| 0.500 |", "Δwall: +10.0 s (+100.0%)")
  end
end
